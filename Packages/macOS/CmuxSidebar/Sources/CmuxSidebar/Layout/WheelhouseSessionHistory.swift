public import CmuxSwiftRender
public import Foundation

/// One agent session that was started in a project's workspace, kept after it ends.
public struct WheelhouseSessionRecord: Codable, Equatable, Sendable {
    /// Unique within the project: the harness's session id, or the agent's slot and start
    /// time when its harness reports none.
    public var id: String
    /// The harness's id, such as `claude`, `codex` or a registered agent's id.
    public var kind: String
    /// The harness's display name.
    public var name: String
    /// The harness's own session id, when it reports one.
    public var sessionId: String?
    /// What the session was asked first.
    public var title: String?
    public var startedAt: Double
    public var lastSeenAt: Double
    /// Absent while the session is running.
    public var endedAt: Double?
    /// The SSH host the session ran on; absent for this Mac.
    public var host: String?
    public var directory: String?
    /// The shell command that reopens the session.
    public var resume: String?

    public init(
        id: String, kind: String, name: String, sessionId: String? = nil, title: String? = nil,
        startedAt: Double, lastSeenAt: Double, endedAt: Double? = nil, host: String? = nil,
        directory: String? = nil, resume: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sessionId = sessionId
        self.title = title
        self.startedAt = startedAt
        self.lastSeenAt = lastSeenAt
        self.endedAt = endedAt
        self.host = host
        self.directory = directory
        self.resume = resume
    }
}

/// A session that is running now, as the app sees it.
public struct WheelhouseSessionObservation: Equatable, Sendable {
    /// The harness's session id, or the agent's slot when `sessionId` is absent.
    public var id: String
    public var kind: String
    public var name: String
    public var sessionId: String?
    public var title: String?
    public var host: String?
    public var directory: String?
    public var resume: String?

    public init(
        id: String, kind: String, name: String, sessionId: String? = nil, title: String? = nil,
        host: String? = nil, directory: String? = nil, resume: String? = nil
    ) {
        self.id = id
        self.kind = kind
        self.name = name
        self.sessionId = sessionId
        self.title = title
        self.host = host
        self.directory = directory
        self.resume = resume
    }
}

/// A project's sessions, oldest first.
public struct WheelhouseSessionHistory: Equatable, Sendable {
    /// Ended sessions beyond this many are dropped, oldest first.
    public static let limit = 500
    /// How stale a running session's saved `lastSeenAt` may get.
    static let saveInterval: Double = 60
    /// A session last seen longer ago than this ended while the app was not looking.
    static let unseenInterval: Double = 15

    public private(set) var records: [WheelhouseSessionRecord]

    public init(records: [WheelhouseSessionRecord] = []) {
        self.records = records
    }

    public init(data: Data) {
        records = (try? JSONDecoder().decode([WheelhouseSessionRecord].self, from: data)) ?? []
    }

    public func encoded() -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return (try? encoder.encode(records)) ?? Data("[]".utf8)
    }

    /// Brings the history up to date with the sessions running now and says whether it
    /// should be saved. `complete` is false while the app cannot tell which sessions are
    /// gone, and then none is ended.
    public mutating func observe(_ live: [WheelhouseSessionObservation], now: Double, complete: Bool = true) -> Bool {
        var changed = false
        var seen: Set<Int> = []
        for observation in live {
            if let index = openIndex(for: observation) ?? reopenIndex(for: observation) {
                seen.insert(index)
                changed = update(&records[index], with: observation, now: now) || changed
            } else {
                seen.insert(records.count)
                records.append(WheelhouseSessionRecord(
                    id: observation.sessionId == nil ? "\(observation.id)@\(Int(now))" : observation.id,
                    kind: observation.kind, name: observation.name, sessionId: observation.sessionId,
                    title: observation.title, startedAt: now, lastSeenAt: now, host: observation.host,
                    directory: observation.directory, resume: observation.resume))
                changed = true
            }
        }
        if complete {
            for index in records.indices where records[index].endedAt == nil && !seen.contains(index) {
                let lastSeen = records[index].lastSeenAt
                records[index].endedAt = now - lastSeen <= Self.unseenInterval ? now : lastSeen
                changed = true
            }
        }
        let ended = records.filter { $0.endedAt != nil }.count
        if ended > Self.limit {
            var excess = ended - Self.limit
            records.removeAll { record in
                guard excess > 0, record.endedAt != nil else { return false }
                excess -= 1
                return true
            }
            changed = true
        }
        return changed
    }

    /// The sessions that have ended, the latest first.
    public func earlier(limit: Int) -> [WheelhouseSessionRecord] {
        Array(records.filter { $0.endedAt != nil }
            .sorted { ($0.endedAt ?? 0, $0.startedAt) > ($1.endedAt ?? 0, $1.startedAt) }
            .prefix(limit))
    }

    public func record(id: String) -> WheelhouseSessionRecord? {
        records.first { $0.id == id }
    }

    /// A session without an id of its own is a new session each time its slot fills.
    private func openIndex(for observation: WheelhouseSessionObservation) -> Int? {
        records.firstIndex { record in
            guard record.endedAt == nil else { return false }
            return observation.sessionId == nil
                ? record.sessionId == nil && record.id.hasPrefix(observation.id + "@")
                : record.id == observation.id
        }
    }

    /// A session with an id that shows up again was resumed.
    private func reopenIndex(for observation: WheelhouseSessionObservation) -> Int? {
        guard observation.sessionId != nil else { return nil }
        return records.firstIndex { $0.id == observation.id }
    }

    private func update(_ record: inout WheelhouseSessionRecord, with observation: WheelhouseSessionObservation, now: Double) -> Bool {
        var changed = false
        if record.endedAt != nil {
            record.endedAt = nil
            changed = true
        }
        if record.kind != observation.kind || record.name != observation.name {
            record.kind = observation.kind
            record.name = observation.name
            changed = true
        }
        if let title = observation.title, !title.isEmpty, record.title != title {
            record.title = title
            changed = true
        }
        if let resume = observation.resume, record.resume != resume {
            record.resume = resume
            changed = true
        }
        if let directory = observation.directory, record.directory != directory {
            record.directory = directory
            changed = true
        }
        if now - record.lastSeenAt >= Self.saveInterval { changed = true }
        record.lastSeenAt = now
        return changed
    }
}

/// A project's earlier sessions as a custom sidebar reads them (`workspaces[i].sessions`).
public struct WheelhouseSessionList: Equatable, Sendable {
    public static let empty = WheelhouseSessionList(project: "", records: [])

    /// The project file's name without its extension.
    public let project: String
    public let records: [WheelhouseSessionRecord]

    public init(project: String, records: [WheelhouseSessionRecord]) {
        self.project = project
        self.records = records
    }

    public var values: [SwiftValue] {
        records.map { record in
            var fields: [String: SwiftValue] = [
                "id": .string(record.id),
                "project": .string(project),
                "kind": .string(record.kind),
                "name": .string(record.name),
                "startedEpoch": .int(Int(record.startedAt)),
                "link": .string(WheelhouseSessionLink.string(project: project, id: record.id)),
                "canResume": .bool(record.resume != nil && record.host == nil),
            ]
            if let ended = record.endedAt { fields["endedEpoch"] = .int(Int(ended)) }
            if let title = record.title, !title.isEmpty { fields["title"] = .string(title) }
            if let host = record.host { fields["host"] = .string(host) }
            if let directory = record.directory { fields["directory"] = .string(directory) }
            return .object(fields)
        }
    }
}

/// `wheelhouse://session/<project>/<session>`: a session of a project, by the project file's
/// name and the record's id.
public enum WheelhouseSessionLink {
    public static let scheme = "wheelhouse"

    public static func string(project: String, id: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "/")
        let part = { (text: String) in text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text }
        return "\(scheme)://session/\(part(project))/\(part(id))"
    }

    public static func parse(_ url: URL) -> (project: String, id: String)? {
        guard url.scheme?.lowercased() == scheme, url.host?.lowercased() == "session" else { return nil }
        let path = URLComponents(url: url, resolvingAgainstBaseURL: false)?.percentEncodedPath ?? ""
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 2,
              let project = String(parts[0]).removingPercentEncoding, !project.isEmpty,
              let id = String(parts[1]).removingPercentEncoding, !id.isEmpty else { return nil }
        return (project, id)
    }
}

/// What the app reads from a project file (`<home>/projects/<project>.yaml`).
public enum WheelhouseProjectFile {
    /// The project's name: the value of the top-level `name` key.
    public static func name(in text: String) -> String? {
        for line in text.split(whereSeparator: \.isNewline) {
            guard line.hasPrefix("name:") else { continue }
            var value = line.dropFirst("name:".count).trimmingCharacters(in: .whitespaces)
            if let quote = value.first, quote == "\"" || quote == "'" {
                value.removeFirst()
                if let end = value.firstIndex(of: quote) { value = String(value[..<end]) }
            } else if let comment = value.range(of: " #") {
                value = String(value[..<comment.lowerBound]).trimmingCharacters(in: .whitespaces)
            }
            return value.isEmpty ? nil : value
        }
        return nil
    }
}
