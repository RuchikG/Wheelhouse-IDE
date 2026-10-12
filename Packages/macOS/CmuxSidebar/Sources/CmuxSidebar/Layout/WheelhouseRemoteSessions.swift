public import Foundation

/// An agent session running in a terminal on an SSH host, found by asking the host.
public struct WheelhouseRemoteSession: Equatable, Sendable {
    /// The harness's own session id.
    public var id: String
    /// The harness the session counts as: the launcher's when one started the agent.
    public var harness: WheelhouseHarness
    /// The host's id of the terminal the agent runs in, such as `term_…`.
    public var terminal: String
    public var directory: String?
    /// What the session was asked first.
    public var title: String?

    public init(id: String, harness: WheelhouseHarness, terminal: String, directory: String? = nil, title: String? = nil) {
        self.id = id
        self.harness = harness
        self.terminal = terminal
        self.directory = directory
        self.title = title
    }
}

/// Finds the agent sessions in a host's cmux terminals. The app cannot see a remote terminal's
/// processes, so a small Python program is run on the host over `ssh`: it lists the processes
/// that carry a terminal's id in their environment and looks up the session of each one that
/// is a harness's program, the way `WheelhouseHarnessScan` does on this Mac. Which of them is
/// an agent, and under which launcher, is decided here by the same rules as for local ones.
///
/// The host needs `python3` and `/proc`, so this works on Linux hosts.
public enum WheelhouseRemoteSessionProbe {
    /// The variable a host's cmux terminal gives its processes, holding the terminal's id.
    public static let terminalVariable = "CMUX_TUI_TERMINAL_ID"

    /// The arguments that make `python3` run the probe for `harnesses`. The program and the
    /// harness list travel base64-encoded so no quoting of them can go wrong.
    public static func arguments(harnesses: [WheelhouseHarness]) -> [String] {
        let list = (try? JSONEncoder().encode(harnesses)) ?? Data("[]".utf8)
        return [
            "-c", "import base64,sys;exec(base64.b64decode(sys.argv[1]).decode())",
            Data(script.utf8).base64EncodedString(), list.base64EncodedString(),
        ]
    }

    /// The remote shell command that runs the probe.
    public static func command(harnesses: [WheelhouseHarness]) -> String {
        "exec python3 " + arguments(harnesses: harnesses).map(shellWord).joined(separator: " ")
    }

    /// `text` as one word of a POSIX shell command.
    public static func shellWord(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// The sessions the probe's output describes; nil when the output is not the probe's.
    public static func sessions(inOutput output: Data, harnesses: [WheelhouseHarness]) -> [WheelhouseRemoteSession]? {
        guard let reply = try? JSONDecoder().decode(Reply.self, from: output) else { return nil }
        var found: [WheelhouseRemoteSession] = []
        let terminals = Dictionary(grouping: reply.processes, by: \.terminal)
        for terminal in terminals.keys.sorted() {
            let listed = terminals[terminal] ?? []
            let processes = listed.map { process in
                WheelhouseProcess(
                    pid: process.pid, parent: process.parent, name: process.name, arguments: process.arguments,
                    startedAt: process.startedAt, directory: process.directory)
            }
            let sessionByPid = Dictionary(
                listed.compactMap { process in process.session.map { (process.pid, $0) } },
                uniquingKeysWith: { first, _ in first })
            for agent in WheelhouseHarnessMatch.agents(in: processes, harnesses: harnesses) {
                guard let session = sessionByPid[agent.process.pid], WheelhouseHarness.isPlainToken(session.id) else {
                    continue
                }
                found.append(WheelhouseRemoteSession(
                    id: session.id, harness: agent.harness, terminal: terminal,
                    directory: agent.process.directory, title: session.title))
            }
        }
        return found
    }

    /// The command typed into a new terminal on the host to open a session again: the
    /// harness's resume command, run in the folder the session was in.
    public static func resumeInput(resume: String, directory: String?) -> String {
        guard let directory, directory.hasPrefix("/") else { return resume }
        return "cd -- " + shellWord(directory) + " && " + resume
    }

    private struct Reply: Decodable {
        var processes: [Process]
    }

    private struct Process: Decodable {
        var pid: Int
        var parent: Int
        var name: String
        var arguments: [String]
        var startedAt: Double
        var directory: String?
        var terminal: String
        var session: Session?
    }

    private struct Session: Decodable {
        var id: String
        var title: String?
    }

    /// The program run on the host. Its second argument is the harness list as base64 JSON;
    /// a third names a folder to read instead of `/proc`, which the tests use.
    public static let script = #"""
    import base64, glob, json, os, re, sys

    HARNESSES = json.loads(base64.b64decode(sys.argv[2]).decode())
    PROC = sys.argv[3] if len(sys.argv) > 3 else "/proc"
    VARIABLE = b"CMUX_TUI_TERMINAL_ID="
    HEAD = 1024 * 1024
    KNOWN = set(name for harness in HARNESSES for name in (harness.get("process") or []) + (harness.get("launcher") or []))


    def read(path, limit=-1):
        try:
            with open(path, "rb") as file:
                return file.read(limit)
        except OSError:
            return None


    def link(path):
        try:
            return os.readlink(path)
        except OSError:
            return None


    def boot_time():
        for line in (read(PROC + "/stat") or b"").splitlines():
            if line.startswith(b"btime "):
                return float(line.split()[1])
        return 0.0


    def started(pid, boot, ticks):
        stat = read("%s/%s/stat" % (PROC, pid)) or b""
        fields = stat[stat.rfind(b")") + 1:].split()
        try:
            return boot + float(fields[19]) / ticks
        except (IndexError, ValueError):
            return 0.0


    def processes():
        boot = boot_time()
        try:
            ticks = float(os.sysconf("SC_CLK_TCK"))
        except (ValueError, OSError):
            ticks = 100.0
        found = []
        for entry in os.listdir(PROC):
            if not entry.isdigit():
                continue
            terminal = None
            for item in (read("%s/%s/environ" % (PROC, entry)) or b"").split(b"\0"):
                if item.startswith(VARIABLE):
                    terminal = item[len(VARIABLE):].decode("utf-8", "replace")
            if not terminal:
                continue
            stat = read("%s/%s/stat" % (PROC, entry)) or b""
            after = stat[stat.rfind(b")") + 1:].split()
            comm = stat[stat.find(b"(") + 1:stat.rfind(b")")].decode("utf-8", "replace")
            exe = link("%s/%s/exe" % (PROC, entry))
            # A program installed under another file name (a version number) still runs under its own.
            name = comm if comm in KNOWN or not exe else os.path.basename(exe)
            arguments = [
                part.decode("utf-8", "replace")
                for part in (read("%s/%s/cmdline" % (PROC, entry)) or b"").split(b"\0")[:2] if part
            ]
            found.append({
                "pid": int(entry),
                "parent": int(after[1]) if len(after) > 1 and after[1].isdigit() else 0,
                "name": name,
                # The start of the command line only: the rest can hold credentials.
                "arguments": arguments,
                "startedAt": started(entry, boot, ticks),
                "directory": link("%s/%s/cwd" % (PROC, entry)),
                "terminal": terminal,
            })
        return found


    def program(process):
        names = [process["name"]] + [os.path.basename(a) for a in process["arguments"][:1]]
        for harness in HARNESSES:
            if any(name in (harness.get("process") or []) for name in names):
                return harness
        return None


    def plain(text):
        return bool(text) and re.match(r"^[A-Za-z0-9._-]+$", text) is not None


    def session_id(name):
        stem = name.rsplit(".", 1)[0] if "." in name else name
        parts = stem.split("-")
        if len(parts) >= 5:
            tail = "-".join(parts[-5:])
            if re.match(r"^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$", tail):
                return tail
        if len(parts) > 1 and plain(parts[-1]):
            return parts[-1]
        return None


    def names_folder(head, directory):
        first = head.split("\n", 1)[0]
        quoted = json.dumps(directory)
        escaped = quoted.replace("/", "\\/")
        return any(('"cwd":' + gap + form) in first for gap in ("", " ") for form in (quoted, escaped))


    def session_file(folder, since, directory):
        best = None
        for base, _, files in os.walk(os.path.expanduser(folder)):
            for name in files:
                if not name.endswith((".jsonl", ".json")) or session_id(name) is None:
                    continue
                path = os.path.join(base, name)
                try:
                    changed = os.path.getmtime(path)
                except OSError:
                    continue
                if changed < since - 2 or (best and changed <= best[1]):
                    continue
                head = (read(path, 64 * 1024) or b"").decode("utf-8", "replace")
                if names_folder(head, directory):
                    best = (path, changed)
        return best[0] if best else None


    def collect(value, texts):
        if isinstance(value, list):
            for item in value:
                collect(item, texts)
            return
        if not isinstance(value, dict) or value.get("isMeta") is True:
            return
        if value.get("role") == "user":
            content = value.get("content")
            if isinstance(content, str):
                texts.append(content)
            elif isinstance(content, list):
                texts.extend(p["text"] for p in content if isinstance(p, dict) and isinstance(p.get("text"), str))
            return
        if value.get("type") == "user_message" and isinstance(value.get("message"), str):
            texts.append(value["message"])
            return
        for key in sorted(value):
            if isinstance(value[key], (list, dict)):
                collect(value[key], texts)


    def first_prompt(path):
        data = read(path, HEAD)
        if data is None:
            return None
        for line in data.decode("utf-8", "replace").splitlines():
            try:
                entry = json.loads(line)
            except ValueError:
                continue
            if not isinstance(entry, dict) or entry.get("type") == "session_meta":
                continue
            texts = []
            collect(entry, texts)
            for text in texts:
                flat = " ".join(text.split())
                if flat and not flat.startswith("<"):
                    return flat[:160] + "…" if len(flat) > 160 else flat
        return None


    def look_up(process, harness):
        found, path = None, None
        template = harness.get("pidFile")
        if template:
            data = read(os.path.expanduser(template.replace("{pid}", str(process["pid"]))))
            try:
                found = json.loads(data.decode("utf-8")).get("sessionId") if data else None
            except (ValueError, AttributeError):
                found = None
        directory = process["directory"]
        if not found and harness.get("sessionFiles") and directory:
            path = session_file(harness["sessionFiles"], process["startedAt"], directory)
            found = session_id(os.path.basename(path)) if path else None
        if not isinstance(found, str) or not plain(found):
            return None
        if path is None and harness.get("transcript") and directory:
            folder = re.sub(r"[^A-Za-z0-9]", "-", directory)
            path = os.path.expanduser(harness["transcript"].replace("{id}", found).replace("{cwd}", folder))
        session = {"id": found}
        title = first_prompt(path) if path else None
        if title:
            session["title"] = title
        return session


    listed = processes()
    for process in listed:
        harness = program(process)
        session = look_up(process, harness) if harness else None
        if session:
            process["session"] = session
    sys.stdout.write(json.dumps({"processes": listed}))
    """#
}
