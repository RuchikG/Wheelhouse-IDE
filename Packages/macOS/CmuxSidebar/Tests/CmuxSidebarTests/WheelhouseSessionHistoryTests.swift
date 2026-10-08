import CmuxSwiftRender
import Foundation
import Testing
@testable import CmuxSidebar

@Suite struct WheelhouseSessionHistoryTests {
    private func session(_ id: String, kind: String = "claude", title: String? = nil, resume: String? = nil) -> WheelhouseSessionObservation {
        WheelhouseSessionObservation(
            id: "\(kind):\(id)", kind: kind, name: kind.capitalized, sessionId: id, title: title,
            directory: "/work", resume: resume)
    }

    private func remote(_ slot: String) -> WheelhouseSessionObservation {
        WheelhouseSessionObservation(id: slot, kind: "claude", name: "Claude", host: "build-box")
    }

    @Test func recordsASessionWhenItIsFirstSeenAndEndsItWhenItIsGone() {
        var history = WheelhouseSessionHistory()
        do { let changed = history.observe([session("a")], now: 100); #expect(changed) }
        #expect(history.records.map(\.id) == ["claude:a"])
        #expect(history.records[0].startedAt == 100)
        #expect(history.earlier(limit: 10).isEmpty)

        do { let changed = history.observe([session("a")], now: 103); #expect(!changed) }
        do { let changed = history.observe([], now: 106); #expect(changed) }
        #expect(history.records[0].endedAt == 106)
        #expect(history.earlier(limit: 10).map(\.id) == ["claude:a"])
    }

    @Test func aSessionGoneWhileTheAppWasAwayEndedWhenItWasLastSeen() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a")], now: 100)
        _ = history.observe([], now: 5000)
        #expect(history.records[0].endedAt == 100)
    }

    @Test func endsNothingWhileTheRunningSessionsAreNotKnown() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a")], now: 100)
        do { let changed = history.observe([], now: 103, complete: false); #expect(!changed) }
        #expect(history.records[0].endedAt == nil)
    }

    @Test func aResumedSessionIsTheSameRecord() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a")], now: 100)
        _ = history.observe([], now: 110)
        do { let changed = history.observe([session("a")], now: 500); #expect(changed) }
        #expect(history.records.count == 1)
        #expect(history.records[0].startedAt == 100)
        #expect(history.records[0].endedAt == nil)
    }

    @Test func fillsInWhatIsLearnedLater() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a")], now: 100)
        do { let changed = history.observe([session("a", title: "Fix the form", resume: "claude --resume a")], now: 103); #expect(changed) }
        #expect(history.records[0].title == "Fix the form")
        #expect(history.records[0].resume == "claude --resume a")
        do { let changed = history.observe([session("a")], now: 106); #expect(!changed) }
        #expect(history.records[0].title == "Fix the form")
    }

    @Test func aSessionFoundToRunUnderALauncherTakesItsName() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([WheelhouseSessionObservation(id: "a", kind: "claude", name: "Claude Code", sessionId: "a")], now: 100)
        let launched = WheelhouseSessionObservation(id: "a", kind: "launcher", name: "Launcher", sessionId: "a")
        do { let changed = history.observe([launched], now: 103); #expect(changed) }
        #expect(history.records.map(\.kind) == ["launcher"])
        #expect(history.records.map(\.name) == ["Launcher"])
    }

    @Test func savesARunningSessionOnceAMinute() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a")], now: 100)
        do { let changed = history.observe([session("a")], now: 130); #expect(!changed) }
        #expect(history.records[0].lastSeenAt == 130)
        do { let changed = history.observe([session("a")], now: 190); #expect(changed) }
    }

    @Test func anAgentWithoutASessionIdIsANewSessionEachRun() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([remote("remote:p1:claude")], now: 100)
        do { let changed = history.observe([remote("remote:p1:claude")], now: 103); #expect(!changed) }
        _ = history.observe([], now: 106)
        _ = history.observe([remote("remote:p1:claude")], now: 200)
        #expect(history.records.map(\.id) == ["remote:p1:claude@100", "remote:p1:claude@200"])
        #expect(history.records.map(\.endedAt) == [106, nil])
        #expect(history.records[1].host == "build-box")
    }

    @Test func listsEarlierSessionsLatestFirst() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a"), session("b", kind: "codex")], now: 100)
        _ = history.observe([session("b", kind: "codex")], now: 110)
        _ = history.observe([session("c")], now: 120)
        #expect(history.earlier(limit: 10).map(\.id) == ["codex:b", "claude:a"])
        #expect(history.earlier(limit: 1).map(\.id) == ["codex:b"])
    }

    @Test func dropsTheOldestEndedSessionsBeyondTheLimit() {
        var history = WheelhouseSessionHistory()
        for index in 0..<(WheelhouseSessionHistory.limit + 3) {
            _ = history.observe([session("s\(index)")], now: Double(index * 10))
        }
        _ = history.observe([session("last")], now: 100_000)
        #expect(history.records.count == WheelhouseSessionHistory.limit + 1)
        #expect(history.records.first?.id == "claude:s3")
        #expect(history.records.last?.id == "claude:last")
    }

    @Test func survivesBeingSaved() {
        var history = WheelhouseSessionHistory()
        _ = history.observe([session("a", title: "Fix the form", resume: "claude --resume a")], now: 100)
        _ = history.observe([], now: 110)
        #expect(WheelhouseSessionHistory(data: history.encoded()) == history)
        #expect(WheelhouseSessionHistory(data: Data("not json".utf8)).records.isEmpty)
    }

    @Test func aLinkNamesTheProjectAndTheSession() throws {
        let link = WheelhouseSessionLink.string(project: "checkout-redesign", id: "claude:7f3a/2c")
        #expect(link == "wheelhouse://session/checkout-redesign/claude:7f3a%2F2c")
        let url = try #require(URL(string: link))
        let parsed = try #require(WheelhouseSessionLink.parse(url))
        #expect(parsed.project == "checkout-redesign")
        #expect(parsed.id == "claude:7f3a/2c")
        let short = try #require(URL(string: "wheelhouse://session/only"))
        #expect(WheelhouseSessionLink.parse(short) == nil)
        let other = try #require(URL(string: "cmux://session/a/b"))
        #expect(WheelhouseSessionLink.parse(other) == nil)
    }

    @Test func aSidebarReadsEarlierSessionsWithTheirLinks() {
        let list = WheelhouseSessionList(project: "checkout", records: [
            WheelhouseSessionRecord(
                id: "claude:a", kind: "claude", name: "Claude Code", sessionId: "a", title: "Fix the form",
                startedAt: 100, lastSeenAt: 160, endedAt: 160, directory: "/work", resume: "claude --resume a"),
            WheelhouseSessionRecord(
                id: "remote:p1:claude@200", kind: "claude", name: "Claude", startedAt: 200, lastSeenAt: 260,
                endedAt: 260, host: "build-box"),
        ])
        #expect(list.values == [
            .object([
                "id": .string("claude:a"), "project": .string("checkout"), "kind": .string("claude"),
                "name": .string("Claude Code"), "startedEpoch": .int(100), "endedEpoch": .int(160),
                "title": .string("Fix the form"), "directory": .string("/work"), "canResume": .bool(true),
                "link": .string("wheelhouse://session/checkout/claude:a"),
            ]),
            .object([
                "id": .string("remote:p1:claude@200"), "project": .string("checkout"), "kind": .string("claude"),
                "name": .string("Claude"), "startedEpoch": .int(200), "endedEpoch": .int(260),
                "host": .string("build-box"), "canResume": .bool(false),
                "link": .string("wheelhouse://session/checkout/remote:p1:claude@200"),
            ]),
        ])
    }

    @Test func readsAProjectFilesName() {
        #expect(WheelhouseProjectFile.name(in: "name: Checkout Redesign\nlane: dev\n") == "Checkout Redesign")
        #expect(WheelhouseProjectFile.name(in: "lane: dev\nname: \"Search: latency\"  # quoted\n") == "Search: latency")
        #expect(WheelhouseProjectFile.name(in: "name: Billing export # nightly\n") == "Billing export")
        #expect(WheelhouseProjectFile.name(in: "agents:\n  - name: agent\n") == nil)
    }
}
