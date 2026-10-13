public import CmuxSwiftRender
public import Foundation

/// A project's own agent, and what any agent of the project is started with: the harness, the
/// brief `proj` writes and the memory the project agent keeps. A custom sidebar reads it as
/// `workspaces[i].projectAgent`.
public struct WheelhouseProjectAgent: Equatable, Sendable {
    /// The `role` of the project agent's sessions in the session history.
    public static let role = "project"

    /// The harness agents of this project are started on; nil when none can be started.
    public var harness: WheelhouseHarness?
    /// Every harness that can be started, for the choice.
    public var harnesses: [WheelhouseHarness]
    /// Whether the project file names its own harness.
    public var hasOwnHarness: Bool
    /// The project agent's running session, and the tab it runs in when the app knows it.
    public var running: WheelhouseSessionRecord?
    public var runningPanel: UUID?
    /// The project agent's latest session that has ended.
    public var last: WheelhouseSessionRecord?
    public var memoryPath: String
    /// When the memory was last written; nil while there is no file.
    public var memoryWrittenAt: Double?
    /// Why agents cannot be started here, in the user's words; nil when they can.
    public var unavailable: String?

    public init(
        harness: WheelhouseHarness?, harnesses: [WheelhouseHarness], hasOwnHarness: Bool = false,
        running: WheelhouseSessionRecord? = nil, runningPanel: UUID? = nil, last: WheelhouseSessionRecord? = nil,
        memoryPath: String, memoryWrittenAt: Double? = nil, unavailable: String? = nil
    ) {
        self.harness = harness
        self.harnesses = harnesses
        self.hasOwnHarness = hasOwnHarness
        self.running = running
        self.runningPanel = runningPanel
        self.last = last
        self.memoryPath = memoryPath
        self.memoryWrittenAt = memoryWrittenAt
        self.unavailable = unavailable
    }

    public func value(project: String) -> SwiftValue {
        let choice = { (harness: WheelhouseHarness) in
            SwiftValue.object(["id": .string(harness.id), "name": .string(harness.name)])
        }
        let session = { (record: WheelhouseSessionRecord) -> [String: SwiftValue] in
            var fields: [String: SwiftValue] = [
                "id": .string(record.id), "project": .string(project), "name": .string(record.name),
                "startedEpoch": .int(Int(record.startedAt)), "canResume": .bool(record.resume != nil),
            ]
            if let ended = record.endedAt { fields["endedEpoch"] = .int(Int(ended)) }
            if let title = record.title, !title.isEmpty { fields["title"] = .string(title) }
            return fields
        }
        var fields: [String: SwiftValue] = [
            "project": .string(project),
            "harnesses": .array(harnesses.map(choice)),
            "hasOwnHarness": .bool(hasOwnHarness),
            "memoryPath": .string(memoryPath),
            "canStart": .bool(unavailable == nil && harness != nil),
        ]
        if let harness { fields["harness"] = choice(harness) }
        if let running {
            var value = session(running)
            if let runningPanel { value["panelId"] = .string(runningPanel.uuidString) }
            fields["running"] = .object(value)
        }
        if let last { fields["last"] = .object(session(last)) }
        if let memoryWrittenAt { fields["memoryEpoch"] = .int(Int(memoryWrittenAt)) }
        if let unavailable { fields["unavailable"] = .string(unavailable) }
        return .object(fields)
    }

    /// Whether a memory file holds anything beyond the headings and the introduction it is
    /// created with (`memoryTemplate` in wheelhouse/board/cmd/proj/brief.go).
    public static func hasNotes(memory text: String) -> Bool {
        text.split(whereSeparator: \.isNewline).contains { line in
            let line = line.trimmingCharacters(in: .whitespaces)
            return !line.isEmpty && !line.hasPrefix("#")
                && !line.hasPrefix("Kept by the project agent for every agent")
                && !line.hasPrefix("what the next agent needs to start work")
        }
    }

    /// What an agent is told first. It names the brief and who the agent is; what each of the
    /// two does is in the brief (`renderBrief` in wheelhouse/board/cmd/proj/brief.go), and a
    /// sidebar tells these messages from a task by how they begin.
    public enum Prompt {
        /// For the project's own agent, which keeps the memory.
        public static func projectAgent(name: String, brief: String) -> String {
            "Project agent for \(name): read \(brief) and follow its section for the project agent."
        }

        /// For any other agent of the project.
        public static func agent(name: String, brief: String) -> String {
            "New agent for \(name): read \(brief) and follow its section for a new agent."
        }

        /// Typed to a running project agent.
        public static func update(brief: String) -> String {
            "Read \(brief) again and bring the project memory up to date, as its section for the project agent says."
        }
    }
}
