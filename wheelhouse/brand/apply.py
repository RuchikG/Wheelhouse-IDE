#!/usr/bin/env python3
"""Rebrand the text of a built app from cmux to Wheelhouse IDE.

Rewrites the compiled string tables inside the app bundle, so no source file or
string catalog changes and upstream merges stay clean. `cmux` is replaced where
it names the app. It is kept where it names something else: the `cmux` command
and its subcommands, file and folder names (cmux.json, ~/.config/cmux), links,
code in backticks, and Manaflow's own products (cmux Cloud, cmux Pro, the iOS
app).

    apply.py <path to .app>     rebrand in place (safe to run again)
    apply.py --self-test
"""

import pathlib
import plistlib
import re
import subprocess
import sys

BRAND = "Wheelhouse IDE"

# Words that make "cmux <word>" a product, a tool, or a command that strings name without
# backticks. Subcommands that are also plain words (open, browser, config) are left out, so
# "keep cmux open" reads as the app; commands in backticks or single quotes are kept anyway.
KEEP_BEFORE = (
    "Cloud", "Pro", "CLI", "automation", "claude-hook", "diff", "docs", "hooks", "mosh-tmux",
    "new-workspace", "notify", "remote", "right-sidebar", "rpc", "shot", "ssh", "ssh-tmux", "vm",
)

# String keys about the CLI's own help text and Manaflow's cloud, mobile and paid features.
SKIP_KEY_PREFIXES = (
    "cli.", "cloud", "machines", "pricing", "mobile", "account", "devices", "proWelcome",
    "teamMembers", "panel.cloudVM", "push.", "notification.teamInvite",
    "notifications.forwardToPhone", "menu.help.upgradeToPro", "pairing",
)

# ASCII classes on purpose: in languages written without spaces the name is followed
# directly by other letters (cmuxについて).
APP_NAME = re.compile(
    r"(?<![A-Za-z0-9_./~\-\[`@])cmux"
    r"(?![A-Za-z0-9_/\]`])"            # cmuxterm, cmux/, [cmux]
    r"(?!\.[A-Za-z0-9])"               # cmux.json, cmux.com (but not a sentence-ending period)
    r"(?!-(?!owned|managed)[A-Za-z0-9])"  # cmux-chat, cmux-tui
    r"(?!://)"
    r"(?! (?:%s)(?![A-Za-z0-9_-]))" % "|".join(re.escape(word) for word in KEEP_BEFORE)
)
CODE_SPAN = re.compile(r"`[^`]*`|'cmux [^']*'")


def rebrand(text: str) -> str:
    """Replace the app name in one string, leaving quoted commands and code spans alone."""
    parts, last = [], 0
    for span in CODE_SPAN.finditer(text):
        parts.append(APP_NAME.sub(BRAND, text[last:span.start()]))
        parts.append(span.group())
        last = span.end()
    parts.append(APP_NAME.sub(BRAND, text[last:]))
    return "".join(parts)


def rebrand_value(value):
    if isinstance(value, str):
        return rebrand(value)
    if isinstance(value, dict):
        return {key: rebrand_value(item) for key, item in value.items()}
    if isinstance(value, list):
        return [rebrand_value(item) for item in value]
    return value


def rebrand_table(path: pathlib.Path) -> int:
    """Rebrand one .strings / .stringsdict file. Returns the number of changed entries."""
    # plutil reads every form a string table comes in (binary, XML, and the UTF-16 text form).
    converted = subprocess.run(
        ["/usr/bin/plutil", "-convert", "binary1", "-o", "-", str(path)], capture_output=True
    )
    if converted.returncode != 0:
        raise SystemExit(f"cannot read {path}: {converted.stderr.decode(errors='replace').strip()}")
    table = plistlib.loads(converted.stdout)
    if not isinstance(table, dict):
        return 0
    changed = 0
    for key, value in table.items():
        if key.startswith(SKIP_KEY_PREFIXES):
            continue
        if path.name == "InfoPlist.strings" and key in ("CFBundleName", "CFBundleDisplayName"):
            new_value = BRAND
        else:
            new_value = rebrand_value(value)
        if new_value != value:
            table[key] = new_value
            changed += 1
    if changed:
        with path.open("wb") as handle:
            plistlib.dump(table, handle, fmt=plistlib.FMT_BINARY)
    return changed


def rebrand_info_plist(path: pathlib.Path) -> int:
    with path.open("rb") as handle:
        info = plistlib.load(handle)
    changed = 0
    for key, value in info.items():
        if key.endswith("UsageDescription") and isinstance(value, str) and rebrand(value) != value:
            info[key] = rebrand(value)
            changed += 1
    if changed:
        with path.open("wb") as handle:
            plistlib.dump(info, handle)
    return changed


def rebrand_app(app: pathlib.Path) -> int:
    resources = app / "Contents" / "Resources"
    if not resources.is_dir():
        raise SystemExit(f"not an app bundle: {app}")
    changed = rebrand_info_plist(app / "Contents" / "Info.plist")
    for path in sorted(resources.rglob("*.strings*")):
        # Contents/Resources/bin holds the CLI and its own string tables.
        if path.suffix in (".strings", ".stringsdict") and "bin" not in path.relative_to(resources).parts:
            changed += rebrand_table(path)
    return changed


def self_test() -> None:
    cases = {
        "Quit cmux?": "Quit Wheelhouse IDE?",
        "About cmux": "About Wheelhouse IDE",
        "cmux": "Wheelhouse IDE",
        "cmux’s updater helper": "Wheelhouse IDE’s updater helper",
        "A program running within cmux would like to use your camera.":
            "A program running within Wheelhouse IDE would like to use your camera.",
        "Open cmux.json": "Open cmux.json",
        "cmux couldn't read ~/.config/cmux/cmux.json.": "Wheelhouse IDE couldn't read ~/.config/cmux/cmux.json.",
        "cmux ssh exited with status %d.": "cmux ssh exited with status %d.",
        "cmux ssh-tmux mirrors a remote tmux server": "cmux ssh-tmux mirrors a remote tmux server",
        "Pick one with: cmux right-sidebar set custom <name>": "Pick one with: cmux right-sidebar set custom <name>",
        "Run `cmux docs` first; cmux opens it.": "Run `cmux docs` first; Wheelhouse IDE opens it.",
        "Upgrade to cmux Pro…": "Upgrade to cmux Pro…",
        "cmux Cloud is unreachable.": "cmux Cloud is unreachable.",
        "The bundled cmux CLI is missing": "The bundled cmux CLI is missing",
        "[cmux] Press Enter to reconnect.": "[cmux] Press Enter to reconnect.",
        "Start the server with cmux-chat": "Start the server with cmux-chat",
        "See https://cmux.com/docs": "See https://cmux.com/docs",
        "A cmux:// link": "A cmux:// link",
        "cmux を終了しますか？": "Wheelhouse IDE を終了しますか？",
        "Wheelhouse IDE is ready": "Wheelhouse IDE is ready",
        "cmuxについて": "Wheelhouse IDEについて",
        "Keep cmux open and confirm": "Keep Wheelhouse IDE open and confirm",
        "opens it in the cmux browser.": "opens it in the Wheelhouse IDE browser.",
        "No cmux browser profile matches '%@'. Run 'cmux browser profiles list'.":
            "No Wheelhouse IDE browser profile matches '%@'. Run 'cmux browser profiles list'.",
        "run cmux automation reload.": "run cmux automation reload.",
        "Open \"%@\" in cmux. Do you want to?": "Open \"%@\" in Wheelhouse IDE. Do you want to?",
        "Edit cmux-owned app settings": "Edit Wheelhouse IDE-owned app settings",
        "Open Full cmux-tui Client": "Open Full cmux-tui Client",
        "com.cmuxterm.app": "com.cmuxterm.app",
    }
    failures = [(text, rebrand(text), want) for text, want in cases.items() if rebrand(text) != want]
    for text, got, want in failures:
        print(f"FAIL {text!r}: got {got!r}, want {want!r}")
    if failures:
        raise SystemExit(1)
    print(f"{len(cases)} cases ok")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    if sys.argv[1] == "--self-test":
        self_test()
        return
    changed = rebrand_app(pathlib.Path(sys.argv[1]))
    print(f"rebranded {changed} strings in {sys.argv[1]}")


if __name__ == "__main__":
    main()
