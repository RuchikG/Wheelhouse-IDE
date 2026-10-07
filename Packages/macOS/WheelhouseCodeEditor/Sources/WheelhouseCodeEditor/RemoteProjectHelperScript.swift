/// The program a remote project editor runs on the remote host, as
/// `python3 -c`. It answers file requests, one JSON object per line in and one
/// per line out, so a whole editing session costs one connection.
enum RemoteProjectHelperScript {
    static let source = #"""
# Runs on the remote host: answers a project editor's file requests, one JSON
# object per line in, one per line out. Works with Python 3.6 and later.
import json, os, re, shutil, sys, time

# argv[1] is this program, as the launcher passed it.
ROOT = sys.argv[2]
REAL_ROOT = os.path.realpath(ROOT)
MAXIMUM_FILE_SIZE = 8 * 1024 * 1024
MAXIMUM_INDEXED_FILES = 20000
HIDDEN = {".git", ".DS_Store"}
UNINDEXED = {".git", "node_modules"}
MAXIMUM_MATCHES = 1000
MAXIMUM_SEARCHED_FILE_SIZE = 1024 * 1024
MAXIMUM_SEARCH_SECONDS = 10.0
MAXIMUM_MATCH_TEXT = 240


class Refused(Exception):
    pass


def inside(path):
    real = os.path.realpath(path)
    return real == REAL_ROOT or real.startswith(REAL_ROOT.rstrip("/") + "/")


def require_inside(path):
    if not inside(path):
        raise Refused("outsideProject")


def require_new(path):
    require_inside(os.path.dirname(path))
    if os.path.lexists(path):
        raise Refused("exists")


def natural(name):
    return [int(part) if part.isdigit() else part.lower() for part in re.split(r"(\d+)", name)]


def units(text):
    # The length the editor counts: UTF-16 units.
    return len(text.encode("utf-16-le")) // 2


def match_in(line, pattern):
    found = pattern.search(line)
    if found is None:
        return None
    at = found.start()
    start = 0
    if len(line) > MAXIMUM_MATCH_TEXT:
        start = max(0, min(at - MAXIMUM_MATCH_TEXT // 4, len(line) - MAXIMUM_MATCH_TEXT))
    text = line[start:start + MAXIMUM_MATCH_TEXT]
    return {
        "column": units(line[:at]) + 1,
        "text": text,
        "matchStart": units(text[:at - start]),
        "matchLength": units(text[at - start:found.end() - start]),
    }


def search(query):
    if not query:
        return {"matches": [], "complete": True}
    # Letter case counts only when the query has a capital letter.
    pattern = re.compile(re.escape(query), 0 if query != query.lower() else re.IGNORECASE)
    deadline = time.time() + MAXIMUM_SEARCH_SECONDS
    matches, complete = [], True
    for folder, folders, names in os.walk(ROOT):
        folders[:] = [name for name in folders if name not in UNINDEXED]
        for name in names:
            if name in HIDDEN:
                continue
            if time.time() > deadline:
                complete = False
                break
            path = os.path.join(folder, name)
            try:
                if not 0 < os.path.getsize(path) <= MAXIMUM_SEARCHED_FILE_SIZE:
                    continue
                with open(path, "rb") as file:
                    data = file.read()
                if b"\0" in data:
                    continue
                content = data.decode("utf-8")
            except (OSError, UnicodeDecodeError):
                continue
            if pattern.search(content) is None:
                continue
            relative = os.path.relpath(path, ROOT)
            for number, line in enumerate(content.split("\n"), 1):
                found = match_in(line[:-1] if line.endswith("\r") else line, pattern)
                if found is None:
                    continue
                if len(matches) == MAXIMUM_MATCHES:
                    complete = False
                    break
                found.update(path=relative, line=number)
                matches.append(found)
            if not complete:
                break
        if not complete:
            break
    matches.sort(key=lambda match: (natural(match["path"]), match["line"]))
    return {"matches": matches, "complete": complete}


def handle(request):
    op, path = request["op"], request["path"]
    if not path.startswith("/"):
        raise Refused("unreadable")
    if op == "list":
        require_inside(path)
        entries = [
            {"name": entry.name, "isDirectory": entry.is_dir()}
            for entry in os.scandir(path)
            if entry.name not in HIDDEN
        ]
        entries.sort(key=lambda entry: (not entry["isDirectory"], natural(entry["name"])))
        return {"entries": entries}
    if op == "read":
        if os.path.getsize(path) > MAXIMUM_FILE_SIZE:
            raise Refused("tooLarge")
        with open(path, "rb") as file:
            data = file.read()
        if b"\0" in data:
            raise Refused("notText")
        try:
            content = data.decode("utf-8")
        except UnicodeDecodeError:
            raise Refused("notText")
        return {"content": content, "modified": os.path.getmtime(path), "readOnly": not inside(path)}
    if op == "write":
        require_inside(path)
        expected = request.get("modified")
        if expected is not None and os.path.exists(path) and abs(os.path.getmtime(path) - expected) > 0.001:
            raise Refused("changedOnDisk")
        with open(path, "wb") as file:
            file.write(request["content"].encode("utf-8"))
        return {"modified": os.path.getmtime(path)}
    if op == "createFile":
        require_new(path)
        open(path, "x").close()
        return {}
    if op == "createDirectory":
        require_new(path)
        os.mkdir(path)
        return {}
    if op == "move":
        destination = request["to"]
        if not inside(path) or os.path.realpath(path) == REAL_ROOT:
            raise Refused("outsideProject")
        if path.lower() != destination.lower():
            require_new(destination)
        else:
            require_inside(destination)
        os.rename(path, destination)
        return {}
    if op == "delete":
        if not inside(path) or os.path.realpath(path) == REAL_ROOT:
            raise Refused("outsideProject")
        if os.path.isdir(path) and not os.path.islink(path):
            shutil.rmtree(path)
        else:
            os.remove(path)
        return {}
    if op == "index":
        paths, complete = [], True
        for folder, folders, names in os.walk(ROOT):
            folders[:] = [name for name in folders if name not in UNINDEXED]
            for name in names:
                if name in HIDDEN:
                    continue
                if len(paths) == MAXIMUM_INDEXED_FILES:
                    complete = False
                    break
                paths.append(os.path.relpath(os.path.join(folder, name), ROOT))
            if not complete:
                break
        paths.sort(key=natural)
        return {"paths": paths, "complete": complete}
    if op == "search":
        return search(request.get("query") or "")
    raise Refused("unsupported")


def main():
    sys.stdout.write(json.dumps({"ready": True, "isDirectory": os.path.isdir(ROOT)}) + "\n")
    sys.stdout.flush()
    for line in sys.stdin:
        try:
            request = json.loads(line)
        except ValueError:
            continue
        reply = {"id": request.get("id"), "ok": True}
        try:
            reply.update(handle(request))
        except Refused as refusal:
            reply = {"id": request.get("id"), "ok": False, "error": str(refusal)}
        except Exception:
            reply = {"id": request.get("id"), "ok": False, "error": "unreadable"}
        sys.stdout.write(json.dumps(reply) + "\n")
        sys.stdout.flush()


main()
"""#
}
