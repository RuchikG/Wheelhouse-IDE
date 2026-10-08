public import Foundation

/// An agent harness whose sessions Wheelhouse IDE can tell apart by looking at the processes
/// of a terminal: which program it is, where it says which session it runs, and how one of
/// its sessions is opened again. Claude Code and Codex are built in; others are listed in
/// `<home>/harnesses.json`.
public struct WheelhouseHarness: Codable, Equatable, Sendable {
    public var id: String
    public var name: String
    /// File names of the agent's program.
    public var process: [String]?
    /// For a launcher: names found in its command line, such as the script it runs.
    public var launcher: [String]?
    /// For a launcher: the harness it starts, whose sessions then count as the launcher's.
    public var wraps: String?
    /// A JSON file the agent writes for its process, with `{pid}` in the path and the session's
    /// id under `sessionId`.
    public var pidFile: String?
    /// A folder (searched with its subfolders) where the agent writes one file per session,
    /// named with the session's id last, as in `rollout-2026-01-02T03-04-05-<id>.jsonl`.
    public var sessionFiles: String?
    /// The session's transcript, for its first prompt: a path with `{id}` and `{cwd}`, the
    /// agent's folder with every character that is not a letter or a digit turned into `-`.
    /// A harness with `sessionFiles` needs none: the session file is read.
    public var transcript: String?
    /// The command that opens a session again, with `{id}` for its id.
    public var resume: String?

    public init(
        id: String, name: String, process: [String]? = nil, launcher: [String]? = nil, wraps: String? = nil,
        pidFile: String? = nil, sessionFiles: String? = nil, transcript: String? = nil, resume: String? = nil
    ) {
        self.transcript = transcript
        self.id = id
        self.name = name
        self.process = process
        self.launcher = launcher
        self.wraps = wraps
        self.pidFile = pidFile
        self.sessionFiles = sessionFiles
        self.resume = resume
    }

    public static let builtIn = [
        WheelhouseHarness(
            id: "claude", name: "Claude Code", process: ["claude"],
            pidFile: "~/.claude/sessions/{pid}.json", transcript: "~/.claude/projects/{cwd}/{id}.jsonl",
            resume: "claude --resume {id}"),
        WheelhouseHarness(
            id: "codex", name: "Codex", process: ["codex"],
            sessionFiles: "~/.codex/sessions", resume: "codex resume {id}"),
    ]

    /// The built-in harnesses with the user's list: an entry of the list replaces the built-in
    /// one of the same id, and launchers come first.
    public static func all(userList data: Data?) -> [WheelhouseHarness] {
        let user = data.flatMap { try? JSONDecoder().decode([WheelhouseHarness].self, from: $0) } ?? []
        let valid = user.filter { !$0.id.isEmpty && !$0.name.isEmpty }
        let ids = Set(valid.map(\.id))
        return valid + builtIn.filter { !ids.contains($0.id) }
    }

    /// The command that opens session `id` again, or nil without a template or with an id
    /// that is not a plain token.
    public func resumeCommand(id: String) -> String? {
        guard let resume, resume.contains("{id}"), Self.isPlainToken(id) else { return nil }
        return resume.replacingOccurrences(of: "{id}", with: id)
    }

    /// Where session `id`, run in `directory`, keeps its transcript.
    public func transcriptPath(id: String, directory: String) -> String? {
        guard let transcript, Self.isPlainToken(id) else { return nil }
        let folder = String(directory.unicodeScalars.map { scalar -> Character in
            scalar.isASCII && CharacterSet.alphanumerics.contains(scalar) ? Character(scalar) : "-"
        })
        return transcript.replacingOccurrences(of: "{id}", with: id).replacingOccurrences(of: "{cwd}", with: folder)
    }

    static func isPlainToken(_ text: String) -> Bool {
        !text.isEmpty && text.unicodeScalars.allSatisfy {
            CharacterSet.alphanumerics.contains($0) || "._-".unicodeScalars.contains($0)
        }
    }

    /// The session id a session file is named with: what follows the last `-` that is not
    /// part of the id, taken as the trailing UUID when there is one.
    public static func sessionId(inFileName name: String) -> String? {
        let stem = (name as NSString).deletingPathExtension
        let parts = stem.split(separator: "-", omittingEmptySubsequences: false)
        if parts.count >= 5 {
            let uuid = parts.suffix(5).joined(separator: "-")
            if UUID(uuidString: uuid) != nil { return uuid }
        }
        guard let last = parts.last, parts.count > 1, isPlainToken(String(last)) else { return nil }
        return String(last)
    }
}

/// A process of a terminal, as the harness matching needs it.
public struct WheelhouseProcess: Equatable, Sendable {
    public var pid: Int
    public var parent: Int
    /// The program's file name.
    public var name: String
    /// The start of its command line: the name it was called by, then its first argument.
    public var arguments: [String]
    public var startedAt: Double
    public var directory: String?

    public init(pid: Int, parent: Int, name: String, arguments: [String] = [], startedAt: Double = 0, directory: String? = nil) {
        self.pid = pid
        self.parent = parent
        self.name = name
        self.arguments = arguments
        self.startedAt = startedAt
        self.directory = directory
    }
}

/// An agent found among a terminal's processes.
public struct WheelhouseHarnessAgent: Equatable, Sendable {
    public var process: WheelhouseProcess
    /// The harness of the agent's own program: where its session id is found.
    public var program: WheelhouseHarness
    /// The harness the session counts as: the launcher's when one started the agent.
    public var harness: WheelhouseHarness

    public init(process: WheelhouseProcess, program: WheelhouseHarness, harness: WheelhouseHarness) {
        self.process = process
        self.program = program
        self.harness = harness
    }
}

public enum WheelhouseHarnessMatch {
    /// The agents among a terminal's processes: every process that is a harness's program and
    /// was not started by another one of them (an agent's own helpers are not agents).
    public static func agents(in processes: [WheelhouseProcess], harnesses: [WheelhouseHarness]) -> [WheelhouseHarnessAgent] {
        let byPid = Dictionary(processes.map { ($0.pid, $0) }, uniquingKeysWith: { first, _ in first })
        func programHarness(_ process: WheelhouseProcess) -> WheelhouseHarness? {
            harnesses.first { harness in
                guard let names = harness.process else { return false }
                return names.contains(process.name)
                    || process.arguments.first.map { names.contains(($0 as NSString).lastPathComponent) } == true
            }
        }
        func ancestors(of process: WheelhouseProcess) -> [WheelhouseProcess] {
            var chain: [WheelhouseProcess] = []
            var seen: Set<Int> = [process.pid]
            var next = byPid[process.parent]
            while let current = next, seen.insert(current.pid).inserted {
                chain.append(current)
                next = byPid[current.parent]
            }
            return chain
        }
        var found: [WheelhouseHarnessAgent] = []
        for process in processes.sorted(by: { $0.pid < $1.pid }) {
            guard let program = programHarness(process) else { continue }
            let chain = ancestors(of: process)
            guard !chain.contains(where: { programHarness($0) != nil }) else { continue }
            let launcher = harnesses.first { harness in
                guard harness.wraps == program.id, let names = harness.launcher, !names.isEmpty else { return false }
                return chain.contains { runs($0, anyOf: names) }
            }
            found.append(WheelhouseHarnessAgent(process: process, program: program, harness: launcher ?? program))
        }
        return found
    }

    /// Whether a process is, or is an interpreter running, one of the named programs.
    static func runs(_ process: WheelhouseProcess, anyOf names: [String]) -> Bool {
        if names.contains(process.name) { return true }
        return process.arguments.prefix(2).contains { names.contains(($0 as NSString).lastPathComponent) }
    }
}

/// What a session was asked first, read from the start of its transcript.
public enum WheelhouseTranscript {
    /// Reads JSON lines as Claude Code and the Codex family write them and returns the first
    /// message the user typed, on one line and cut to a title's length. Text a harness puts
    /// in the user's name (it starts with a tag) is passed over.
    public static func firstPrompt(inLines lines: [Substring]) -> String? {
        for line in lines {
            guard let data = line.data(using: .utf8),
                  let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  object["type"] as? String != "session_meta" else { continue }
            var texts: [String] = []
            collect(object, into: &texts)
            for text in texts {
                let flat = text.split(whereSeparator: \.isWhitespace).joined(separator: " ")
                guard !flat.isEmpty, !flat.hasPrefix("<") else { continue }
                return flat.count > 160 ? String(flat.prefix(160)) + "…" : flat
            }
        }
        return nil
    }

    /// What the user said in a transcript entry, in the entry's own order.
    private static func collect(_ value: Any, into texts: inout [String]) {
        if let list = value as? [Any] {
            for item in list { collect(item, into: &texts) }
            return
        }
        guard let object = value as? [String: Any], object["isMeta"] as? Bool != true else { return }
        if object["role"] as? String == "user" {
            if let text = object["content"] as? String {
                texts.append(text)
            } else if let parts = object["content"] as? [[String: Any]] {
                texts += parts.compactMap { $0["text"] as? String }
            }
            return
        }
        if object["type"] as? String == "user_message", let text = object["message"] as? String {
            texts.append(text)
            return
        }
        for key in object.keys.sorted() {
            if let nested = object[key], nested is [Any] || nested is [String: Any] { collect(nested, into: &texts) }
        }
    }

    /// Whether a session file, by its first line, belongs to an agent run in `directory`.
    public static func sessionFileHead(_ head: String, isIn directory: String) -> Bool {
        let first = head.prefix { !$0.isNewline }
        guard let data = try? JSONEncoder().encode(directory), let quoted = String(data: data, encoding: .utf8) else {
            return false
        }
        let plain = quoted.replacingOccurrences(of: "\\/", with: "/")
        return ["\"cwd\":" + plain, "\"cwd\": " + plain, "\"cwd\":" + quoted, "\"cwd\": " + quoted]
            .contains { first.contains($0) }
    }
}
