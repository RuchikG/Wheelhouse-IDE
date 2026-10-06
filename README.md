# Wheelhouse

Wheelhouse is a fork of [cmux](https://github.com/manaflow-ai/cmux), the Ghostty-based macOS
terminal for AI coding agents. The goal is to run every project you have in flight from one
window: a board of projects, and for each project a workspace with its terminals, agents, browser
tabs and code. It adds three things to cmux: a project board, a built-in code editor, and
notifications from agents running on SSH hosts.

This is an early personal fork. It is not affiliated with or supported by Manaflow, and there are
no packaged releases; you build it from source. Everything cmux does (workspaces, splits,
notifications, the in-app browser, the CLI, remote workspaces) works as it does upstream, and the
[cmux documentation](https://cmux.com/docs/getting-started) applies.

## What Wheelhouse adds

### Code editor

Text files open in a [Monaco](https://microsoft.github.io/monaco-editor/) editor (the editor
from VS Code) instead of cmux's native text view. It lives inside the existing file panel, so
opening files from the file explorer or `cmux open <file>`, the dirty marker, save and revert,
reload when the file changes on disk, and session restore all work as before.

- Syntax highlighting for about 80 languages, loaded on demand.
- Monaco's editing features: multiple cursors, find and replace, folding, minimap, bracket matching.
- Save with ⌘S or the panel's save button.
- While the editor has keyboard focus, ⌘F (find in file), ⌘D (add the next occurrence to the
  selection) and ⌘/ (toggle line comment) go to the editor. Everywhere else they keep their cmux
  meaning, for example ⌘D splits the pane.
- A new-editor-tab button (curly braces) sits next to the new-terminal and new-browser buttons at
  the top right of every pane. It offers "New Untitled File", "Open File…" and "Open Folder…"; a
  file that is already open is focused instead of opened twice. A tab's right-click menu has the
  same choices under "New Editor Tab to Right". The button is the built-in action
  `wheelhouse.newEditor`, so it can be placed or removed like any other tab bar button in
  `cmux.json`.
- An untitled file asks where to save the first time you save it, and the tab then becomes that
  file. Its text is not kept if the app quits before that.
- Follows the panel's light or dark colors and the existing `fileEditor.*` settings (word wrap,
  line numbers, indent guides, current-line highlight, tab width).

#### Folder tabs

"Open Folder…" opens a folder as one tab that works like a small editor window: the folder's file
tree on the left, a strip of the files you have opened from it, and the editor.

- Folders load when expanded. `.git` is hidden. The tree and the open file are refreshed when the
  window regains focus, and with the ↻ button.
- ⌘S saves the open file. A dot marks a file with unsaved edits, and the tab itself shows one
  while any file has them. Closing such a file asks whether to save.
- If something else (an agent, a terminal command) changed a file after it was opened here, saving
  asks before overwriting. A file with no unsaved edits just picks up the change.
- Go to definition and similar jumps open the target inside the same tab. Files outside the
  folder, such as a dependency's source, open read-only.
- The language server is rooted at the folder and shared by every file in the tab.

From a script, `wheelhouse/cli rpc file.open '{"paths":["/path/to/folder"]}'` opens a folder tab.

#### Language servers

Go files get completion, hover, go to definition, find references, rename, formatting and
diagnostics from [gopls](https://go.dev/gopls/), when `gopls` is installed (`go install
golang.org/x/tools/gopls@latest`). The app looks for it on your login shell's `PATH`. Each editor
runs `gopls -remote=auto`, a thin client of one shared gopls daemon, so open files of the same
module share one loaded workspace. The project root is the nearest `go.work`, else `go.mod`, above
the file. A jump to another file opens that file as a tab in the same pane.

Not yet: a rename that would also change a file that is not open is refused as a whole, and the
⌘-hover preview of a definition stays empty when its file is not open (the jump itself works).

Other servers that speak LSP over standard input and output can be added, by file extension:

```sh
defaults write <bundle id> wheelhouse.languageServers -dict-add rs \
  '{ command = ("rust-analyzer"); rootMarkers = ("Cargo.toml"); }'
```

An entry with an empty `command` turns a built-in server off. Server start-up and failures are
logged under the `wheelhouse.code-editor` subsystem, category `language-server`.

Not there yet:

- A folder tab does not remember its open files across a restart, and has no file search,
  create, rename or delete yet.
- If a language server exits, its features stay off in that tab until the tab is reopened.
- Remote files are read-only, as in cmux.
- Markdown source editing still uses the native editor.
- Other editor shortcuts that overlap an app shortcut still go to the app.

To go back to the native editor:

```sh
defaults write <bundle id> wheelhouse.codeEditor.enabled -bool false
```

The bundle id is `com.cmuxterm.app.debug.<tag>`, so `com.cmuxterm.app.debug.wheelhouse` by default.

### Project board

A kanban board of projects in the left sidebar, replacing the flat workspace list.

```
Projects
DESIGN            1
  ● Checkout redesign
    Tech design in review
DEV               2
  ● Search indexing        2 waiting on you
    feat/reindex* · #482 · 3 agents
  ● Billing export         remote
    feat/export · 60%
REVIEW & TEST     —
RELEASE           1
  ● Mobile login
    Rollout 50% → 100% Wednesday
DONE              —
```

How it maps onto cmux:

| Board | cmux |
| --- | --- |
| Project (a card) | A workspace: its directory, terminals, agents and browser tabs |
| Lane | A workspace group. Moving a card moves the workspace between groups |
| Card details | The workspace's description, git branch and pull request, agents and their status, unread notifications, progress |
| The board itself | A [custom sidebar](docs/custom-sidebars.md) script |

Design:

- **Five lanes:** Design, Dev, Review & Test, Release, Done. A project moves left to right over
  its life; lanes are set by hand.
- **A card shows what needs you.** Status dot, one-line summary, branch (with a dirty marker) and
  pull request, how many agents are running and how many are waiting on you, unread count, a
  badge for projects on a remote host, and a progress bar.
- **Waiting-on-you first.** Within a lane, projects with an agent waiting for input sort to the
  top, then projects with unread notifications.
- **Click to jump.** Clicking a card selects the project's workspace, and goes straight to the
  agent that is waiting if there is one. Right-click moves the card to another lane or marks it
  read.
- **Links are chips on the card,** not tabs that stay open. A project's pages (a ticket, a design
  document, a pipeline) show as small chips: icons on every card, with their names on the
  selected one. Clicking a chip opens the page as a browser tab in the project's workspace, or
  shows the tab if it is already open; an open link's chip is tinted. Close the tab when you are
  done, from the tab or from the chip's right-click menu, and the chip stays for next time.
- **The board only reads state, jumps and opens links.** Work happens in the project's workspace:
  in its terminals and agents, in the real web tools opened as browser tabs, and in the editor.
  Nothing is re-implemented on the board.
- **Workspaces that are not projects** are listed under "Not on the board" and can be added to a
  lane from there.
- **A project is one small file:** name, lane, summary, repositories with their branch, links
  for the card, and agents to start. Opening a project creates its workspace in the right lane,
  starts the agents, and gives it its own git worktree per repository, so two projects on the
  same repository never share a checkout.
- **Remote projects** are ordinary cmux SSH workspaces; the card carries a badge.

The board is built on cmux's own extension points (custom sidebars, workspace groups and the
CLI), so it needs no changes to the app and also works with stock cmux. The sidebar script and
`proj`, the small CLI that creates lanes and opens projects, are in
[`wheelhouse/board`](wheelhouse/board/README.md), with set-up steps.

### Notifications from agents on SSH hosts

cmux tells you when an agent on your Mac needs input or finishes, but an agent in a `cmux ssh`
workspace is silent in current cmux releases. A small Claude Code hook, installed on the SSH host
with one command, forwards those moments through the cmux relay, so the workspace and its board
card show an unread notification. It stays out of the way for headless jobs and steps aside on
cmux builds whose relay reports agent status itself. See
[`wheelhouse/remote-notify`](wheelhouse/remote-notify/README.md).

### Roadmap

| Step | State |
| --- | --- |
| Editor in the file panel | Done |
| LSP: completion, definitions, hover, diagnostics (gopls first) | Done |
| Remote workspaces: edit and save files over SSH, language server on the remote host | Planned |
| Project board: lanes, cards, project files, a worktree per project | Done |
| Notifications from agents on SSH hosts | Done |
| Agent status (working, waiting, idle) for SSH hosts on the board | Planned |
| Board: drag cards between lanes; status from external tools (issue tracker, CI) on the card | Planned |

## Build

Requirements: macOS 14 or later, Xcode 26 or later with the Metal toolchain component, Zig and
Rust. Rebuilding the web bundle also needs [bun](https://bun.sh).

```sh
git clone https://github.com/RuchikG/Wheelhouse-IDE.git
cd Wheelhouse-IDE
./scripts/setup.sh
wheelhouse/build.sh     # first build: around 25 minutes
wheelhouse/open.sh
```

`wheelhouse/build.sh` produces `Wheelhouse IDE.app`. It is a tagged dev build of cmux with its own
bundle id, settings and socket, so it runs next to an installed cmux without touching it. Drive it
from a terminal with `wheelhouse/cli`, which is the `cmux` command pointed at this app:

```sh
wheelhouse/cli open path/to/file.go
```

The build stays off the cmux cloud backend. Sign-in, cloud machines and mobile pairing are upstream
features that need Manaflow's services and are not part of what this fork is for.

`WHEELHOUSE_TAG` (default `wheelhouse`) names the build; a different tag is a separate app with
separate settings.

The build also sets a few preferences (`wheelhouse/defaults.sh`) that hide cmux's own account
control, its Pro upgrade prompts, the phone pairing button and the red dev-build label. They are
ordinary cmux switches, so they can be turned back on from the app's debug menu.

### Nothing reported to cmux

`wheelhouse/defaults.sh` also turns off "Send anonymous telemetry". In cmux that setting stops
usage analytics and crash reports but still asks cmux's feature-flag service for flag values every
30 minutes. In this fork it stops that request too: with telemetry off, flags use their built-in
defaults and local overrides. A fork has no business in cmux's analytics or crash reports, and its
bundle id still starts with cmux's, so cmux's own check for foreign builds would not have caught
it. Turn the setting back on in Settings to get upstream's behavior.

### Naming

The app is named Wheelhouse IDE, and its menus, dialogs and settings say Wheelhouse IDE where
cmux's say cmux. This is done after the build, by rewriting the app's compiled text
(`wheelhouse/brand/apply.py`) in all 20 languages, so no upstream source or translation file is
edited.

Some names are cmux's on purpose, because scripts, documentation and the remote daemon depend on
them: the `cmux` command and its subcommands, `~/.config/cmux` and `cmux.json`, `CMUX_*`
environment variables, the bundle id prefix, and the process name. cmux Cloud, cmux Pro and the
iOS app are Manaflow's products and keep their names.

The icon, a terminal prompt inside a ship's wheel, has a dark and a light variant, drawn in
`wheelhouse/brand/icon/wheelhouse-ide-dark.svg` and `wheelhouse-ide-light.svg`. The running app
shows the one that matches its theme (Settings → Themes: System, Light or Dark) and switches with
it. cmux's separate App Icon setting is removed, so the icon and the theme cannot disagree. Finder,
and the Dock before the app has started, show the dark variant. `wheelhouse/brand/icon/generate.sh`
renders both SVGs into the asset catalog; run it after changing one, then rebuild. The release,
nightly and RC icon sets are still cmux's.

## Where the fork's code is

| Path | What |
| --- | --- |
| `Packages/macOS/WheelhouseCodeEditor` | Swift package: the web view host, a private URL scheme that serves the bundled editor, the bridge to the page, language server processes, file access for folder tabs, unit tests |
| `Sources/Panels/FilePreviewCodeEditor.swift` | Adapters between the file panel and the editor, for a file and for a folder |
| `Sources/Panels/FilePreviewNewEditorTab.swift` | The new-editor-tab action: untitled files, the file and folder choosers, the right-click menu item |
| `webviews/src/code-editor`, `webviews/src/surfaces/codeEditorSurface.ts` | The editor page: single-file editor, folder view, language client |
| `Resources/markdown-viewer/webviews-app` | Built web bundle (generated; do not edit) |
| `wheelhouse/board` | The project board: sidebar script, the `proj` CLI (Go), examples |
| `wheelhouse/remote-notify` | Claude Code hook for SSH hosts and its installer |
| `wheelhouse/build.sh`, `open.sh`, `cli` | Build, open and drive Wheelhouse IDE |
| `wheelhouse/defaults.sh` | Preferences the build applies on top of cmux's defaults |
| `wheelhouse/brand` | The post-build step that names the app's text Wheelhouse IDE, and the icon source |

After changing anything under `webviews/`, regenerate the bundle:

```sh
./scripts/build-webviews-app.sh
```

Run the editor package's tests with `swift test` in `Packages/macOS/WheelhouseCodeEditor`. Page
errors and failed asset loads are logged under the `wheelhouse.code-editor` subsystem:

```sh
/usr/bin/log show --last 5m --predicate 'subsystem == "wheelhouse.code-editor"'
```

## Staying close to upstream

cmux moves quickly, so the fork keeps its changes small: new code goes in its own package and
files, and upstream files are touched only where the editor hooks in (the file panel, the app's
key monitor, the built-in tab bar actions) and for the one-line telemetry rule in
`Sources/FeatureFlags.swift`. The tab right-click menu is built by the Bonsplit submodule, which
this fork does not modify: the editor item is added to that menu when it opens. `upstream` is
`manaflow-ai/cmux`; merge it regularly. `README.md`, the generated web bundle and the icon images are the
files most likely to conflict; keep this README, regenerate the bundle after a merge, and rerun
`wheelhouse/brand/icon/generate.sh` if upstream changes its icons.

The translated `README.*.md` files are upstream's and describe cmux, not this fork.

## License

Wheelhouse is licensed like cmux: GPL-3.0-or-later for the app, CLI and packages, with the
server directories listed in [LICENSE](LICENSE) under the Business Source License 1.1. cmux is
copyright Manaflow, Inc. and its contributors; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
for bundled dependencies. Monaco Editor is MIT-licensed, copyright Microsoft Corporation.
