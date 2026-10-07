import AppKit
import CmuxControlSocket
import CmuxSettings
import SwiftUI

/// The project board from inside the app: the first-launch set-up and the New Project form.
/// Both hand the work to `proj`, the board's command, which ships in the app bundle.
enum WheelhouseProjects {
    struct Lane: Identifiable, Hashable {
        let key: String
        let title: String
        var id: String { key }
    }

    /// The lanes `proj` knows (wheelhouse/board/cmd/proj/manifest.go).
    static let lanes = [
        Lane(key: "design", title: "Design"),
        Lane(key: "dev", title: "Dev"),
        Lane(key: "review", title: "Review & Test"),
        Lane(key: "release", title: "Release"),
        Lane(key: "done", title: "Done"),
    ]

    struct Outcome: Sendable {
        let succeeded: Bool
        let output: String

        /// The last thing `proj` said, without its own name in front.
        var message: String {
            let line = output.split(separator: "\n").last.map(String.init) ?? ""
            return line.hasPrefix("proj: ") ? String(line.dropFirst("proj: ".count)) : line
        }
    }

    static let boardSetUpKey = "wheelhouse.board.setUp"

    private static var commandURL: URL? {
        guard let url = Bundle.main.resourceURL?.appendingPathComponent("bin/proj"),
              FileManager.default.isExecutableFile(atPath: url.path) else { return nil }
        return url
    }

    private static var socketPath: String {
        TerminalController.shared.activeSocketPath(preferredPath: SocketControlSettings.socketPath())
    }

    /// Runs `proj` against this app and waits for it off the main thread. `home` is the
    /// directory of the project files when it is not the default one.
    static func run(_ arguments: [String], home: String? = nil) async -> Outcome {
        guard let commandURL,
              let cliURL = Bundle.main.resourceURL?.appendingPathComponent("bin/cmux") else {
            return Outcome(succeeded: false, output: String(
                localized: "wheelhouse.projects.commandMissing",
                defaultValue: "This build does not include the board command."
            ))
        }
        var environment = ProcessInfo.processInfo.environment
        environment["CMUX_SOCKET_PATH"] = socketPath
        environment["CMUX_BUNDLED_CLI_PATH"] = cliURL.path
        environment["CMUX_BIN"] = cliURL.path
        if let home, !home.isEmpty {
            environment["WHEELHOUSE_HOME"] = home
        }
        // The app may itself have been started from a terminal of another cmux.
        for key in ["CMUX_SOCKET", "CMUX_WORKSPACE_ID", "CMUX_SURFACE_ID", "CMUX_TAB_ID", "CMUX_PANEL_ID"] {
            environment.removeValue(forKey: key)
        }
        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let process = Process()
                process.executableURL = commandURL
                process.arguments = arguments
                process.environment = environment
                process.standardInput = FileHandle.nullDevice
                let pipe = Pipe()
                process.standardOutput = pipe
                process.standardError = pipe
                do {
                    try process.run()
                } catch {
                    continuation.resume(returning: Outcome(succeeded: false, output: error.localizedDescription))
                    return
                }
                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                process.waitUntilExit()
                let output = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: Outcome(succeeded: process.terminationStatus == 0, output: output))
            }
        }
    }

    /// Creates the lanes, installs and shows the board and adds the example project, once per
    /// install. It waits for the first window because `proj` works through the control socket.
    @MainActor
    static func setUpBoardOnFirstLaunch() {
        let environment = ProcessInfo.processInfo.environment
        guard !UserDefaults.standard.bool(forKey: boardSetUpKey), commandURL != nil,
              environment["XCTestConfigurationFilePath"] == nil, environment["CMUX_UI_TEST_MODE"] != "1"
        else { return }
        Task { @MainActor in
            var ready = false
            for _ in 0..<120 where !ready {
                try? await Task.sleep(nanoseconds: 500_000_000)
                ready = AppDelegate.shared?.tabManager?.selectedWorkspace != nil
                    && TerminalController.shared.socketListenerHealth(expectedSocketPath: socketPath).isHealthy
            }
            guard ready else { return }
            let outcome = await run(["init"])
            if outcome.succeeded {
                UserDefaults.standard.set(true, forKey: boardSetUpKey)
            } else {
                NSLog("Wheelhouse IDE: the board was not set up: %@", outcome.output)
            }
        }
    }

    @MainActor private static var boardRun: Task<Void, Never>?

    /// A change made on the board (a link, a lane, a project opened again): `proj` runs out
    /// of sight, one change after another, and a failure is shown with what it said.
    @MainActor
    static func runForBoard(_ arguments: [String], home: String?, failure: String?) {
        let previous = boardRun
        boardRun = Task { @MainActor in
            await previous?.value
            let outcome = await run(arguments, home: home)
            guard !outcome.succeeded else { return }
            NSLog("Wheelhouse IDE: proj %@ failed: %@", arguments.joined(separator: " "), outcome.output)
            let alert = NSAlert()
            alert.alertStyle = .warning
            if let failure, !failure.isEmpty {
                alert.messageText = failure
            } else {
                alert.messageText = String(
                    localized: "wheelhouse.projects.changeFailed",
                    defaultValue: "The board could not make that change."
                )
            }
            alert.informativeText = outcome.message
            if let window = NSApp.keyWindow ?? NSApp.mainWindow {
                alert.beginSheetModal(for: window) { _ in }
            } else {
                alert.runModal()
            }
        }
    }

    @MainActor
    static func showNewProject() {
        WheelhouseNewProjectWindowController.shared.show()
    }
}

@MainActor
final class WheelhouseNewProjectWindowController: NSObject, NSWindowDelegate {
    static let shared = WheelhouseNewProjectWindowController()
    /// Listed in `cmuxAuxiliaryWindowIdentifiers`, so ⌘W closes this window and not a tab.
    nonisolated static let windowIdentifier = "cmux.wheelhouse.newProject"

    private var window: NSWindow?

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: WheelhouseNewProjectView { [weak self] in
                self?.window?.close()
            })
            let window = NSWindow(contentViewController: hosting)
            window.styleMask = [.titled, .closable]
            window.title = String(localized: "wheelhouse.newProject.title", defaultValue: "New Project")
            window.identifier = NSUserInterfaceItemIdentifier(Self.windowIdentifier)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            self.window = window
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

struct WheelhouseNewProjectView: View {
    let close: () -> Void

    @State private var name = ""
    @State private var folder = ""
    @State private var lane = WheelhouseProjects.lanes[0].key
    @State private var summary = ""
    @State private var agentCommand = ""
    @State private var isCreating = false
    @State private var failure = ""
    @FocusState private var nameIsFocused: Bool

    private var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Form {
                TextField(
                    String(localized: "wheelhouse.newProject.name", defaultValue: "Name"),
                    text: $name,
                    prompt: Text(String(localized: "wheelhouse.newProject.name.prompt", defaultValue: "Checkout redesign"))
                )
                .focused($nameIsFocused)
                .accessibilityIdentifier("WheelhouseNewProjectName")

                HStack(spacing: 8) {
                    TextField(
                        String(localized: "wheelhouse.newProject.folder", defaultValue: "Folder"),
                        text: $folder,
                        prompt: Text(String(localized: "wheelhouse.newProject.folder.prompt", defaultValue: "Your home folder"))
                    )
                    .accessibilityIdentifier("WheelhouseNewProjectFolder")
                    Button(String(localized: "wheelhouse.newProject.chooseFolder", defaultValue: "Choose…")) {
                        chooseFolder()
                    }
                }

                Picker(String(localized: "wheelhouse.newProject.lane", defaultValue: "Lane"), selection: $lane) {
                    ForEach(WheelhouseProjects.lanes) { lane in
                        Text(lane.title).tag(lane.key)
                    }
                }

                TextField(
                    String(localized: "wheelhouse.newProject.summary", defaultValue: "Summary"),
                    text: $summary,
                    prompt: Text(String(localized: "wheelhouse.newProject.summary.prompt", defaultValue: "One line for the card (optional)"))
                )

                TextField(
                    String(localized: "wheelhouse.newProject.agent", defaultValue: "Start with"),
                    text: $agentCommand,
                    prompt: Text(String(
                        localized: "wheelhouse.newProject.agent.prompt",
                        defaultValue: "A command to run, such as claude (optional)"
                    ))
                )
            }

            if !failure.isEmpty {
                Text(failure)
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("WheelhouseNewProjectFailure")
            }

            HStack {
                Spacer()
                if isCreating {
                    ProgressView().controlSize(.small)
                }
                Button(String(localized: "wheelhouse.newProject.cancel", defaultValue: "Cancel"), role: .cancel) {
                    close()
                }
                .keyboardShortcut(.cancelAction)
                Button(String(localized: "wheelhouse.newProject.create", defaultValue: "Create")) {
                    create()
                }
                .keyboardShortcut(.defaultAction)
                .disabled(trimmedName.isEmpty || isCreating)
                .accessibilityIdentifier("WheelhouseNewProjectCreate")
            }
        }
        .padding(20)
        .frame(width: 460)
        .onAppear { nameIsFocused = true }
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = String(localized: "wheelhouse.newProject.chooseFolder.prompt", defaultValue: "Choose")
        if panel.runModal() == .OK, let url = panel.url {
            folder = (url.path as NSString).abbreviatingWithTildeInPath
        }
    }

    private func create() {
        var arguments = ["new", "--name", trimmedName, "--lane", lane]
        for (flag, value) in [("--dir", folder), ("--summary", summary), ("--agent", agentCommand)] {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                arguments += [flag, trimmed]
            }
        }
        isCreating = true
        failure = ""
        Task { @MainActor in
            let outcome = await WheelhouseProjects.run(arguments)
            isCreating = false
            if outcome.succeeded {
                close()
            } else {
                failure = outcome.message
            }
        }
    }
}
