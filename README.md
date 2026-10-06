<p align="center">
  <img src="wheelhouse/brand/icon/wheelhouse-ide-dark.svg" width="128" alt="Wheelhouse IDE icon">
</p>

<h1 align="center">Wheelhouse IDE</h1>

<p align="center">
  One window for every project you have in flight:<br>
  a board of projects, and for each one a workspace with its terminals, AI coding agents, browser tabs and code.
</p>

Wheelhouse IDE is a macOS app built on [cmux](https://github.com/manaflow-ai/cmux), the
Ghostty-based terminal for AI coding agents. It keeps everything cmux does and adds a project
board, a code editor with language servers, and editing on remote hosts.

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

## Features

- **Project board.** A kanban board in the sidebar: one card per project, in lanes from Design to
  Done. A card shows its branch and pull request, how many agents are running and how many are
  waiting on you, and links to the project's documents. Click a card to jump into its workspace.
- **Code editor.** Text files open in [Monaco](https://microsoft.github.io/monaco-editor/), the
  editor from VS Code: syntax highlighting for about 80 languages, multiple cursors, find and
  replace, folding and a minimap.
- **Folder tabs.** Open a folder as one tab with a file tree, a strip of open files, file search
  by name, and create, rename and delete from the tree.
- **Language servers.** Completion, hover, go to definition, references, rename and diagnostics.
  Go works out of the box with `gopls`; any other LSP server can be added with one setting.
- **Remote hosts.** Open a folder on another machine over SSH. Files are edited and saved there,
  and the language server runs there. For this the host needs only `python3`.
- **Agent notifications from SSH hosts.** A small Claude Code hook tells you when an agent on a
  remote machine needs input or has finished.
- **Everything in cmux.** Workspaces, splits, notifications, the in-app browser and the `cmux`
  command work as they do upstream, and the
  [cmux documentation](https://cmux.com/docs/getting-started) applies.

## Install

1. Download `Wheelhouse-IDE-<version>-macos-universal.zip` from the
   [latest release](https://github.com/RuchikG/Wheelhouse-IDE/releases/latest) and unzip it.
2. Move `Wheelhouse IDE.app` to your Applications folder and open it.
3. macOS blocks it the first time, because the build is not signed with an Apple Developer ID.
   Open System Settings → Privacy & Security, find the message about Wheelhouse IDE and click
   "Open Anyway".

It needs macOS 14 or later and runs on Apple silicon and Intel. The app has its own settings and
runs next to an installed cmux without touching it.

To build it yourself, see [Building from source](wheelhouse/docs/building.md).

## Getting started

1. **Open a folder.** Click the curly-braces button at the top right of a pane and choose
   "Open Folder…". The folder opens as a tab with its file tree.
2. **Set up the board.** In a terminal inside the app, run `proj init`. It creates the lanes and
   a folder for your project files with a template to copy:
   [board set-up](wheelhouse/board/README.md).
3. **Work on a remote host.** Run `cmux ssh <host>` in the app to open a workspace on that
   machine (this installs cmux's remote daemon there), then choose "Open Folder…": it asks for
   a path on the host. If the connection fails, see
   [Folders on a remote host](wheelhouse/docs/editor.md#folders-on-a-remote-host).
4. **Agent status from remote hosts (optional).** cmux can show whether the agents in a
   `cmux ssh` workspace are working or waiting for you. That needs its hooks in the host's
   Claude Code and Codex settings, so Wheelhouse IDE leaves it off until you ask:

   ```sh
   defaults write com.cmuxterm.app.staging.wheelhouse wheelhouse.remoteAgentHooks.enabled -bool true
   ```

   Read [what it changes on the host](wheelhouse/docs/fork.md#agent-hooks-on-ssh-hosts) first.

The `cmux` command works in the app's terminals as it does in cmux.

## Documentation

| Topic | |
| --- | --- |
| [Code editor](wheelhouse/docs/editor.md) | Editing, folder tabs, remote folders, language servers, known limits |
| [Project board](wheelhouse/docs/board.md) | How the board works and how it maps onto cmux |
| [Board set-up and the `proj` command](wheelhouse/board/README.md) | Lanes, project files, links, worktrees, settings |
| [Notifications from SSH hosts](wheelhouse/remote-notify/README.md) | Installing the hook on a remote machine |
| [Building from source](wheelhouse/docs/building.md) | Requirements, build tags, the command line |
| [How the fork differs from cmux](wheelhouse/docs/fork.md) | Privacy, naming, where the code is, merging upstream |

## Roadmap

| | State |
| --- | --- |
| Code editor with language servers | Done |
| Folder tabs, on this Mac and on remote hosts | Done |
| Project board: lanes, cards, links, a git worktree per project | Done |
| Notifications from agents on SSH hosts | Done |
| Search inside files | Planned |
| Saving single remote files back to the host | Planned |
| Agent status (working, waiting, idle) for SSH hosts on the board | Planned |
| Dragging cards between lanes; status from issue trackers and CI on the card | Planned |

## Relationship to cmux

Wheelhouse IDE is an independent fork. It is not affiliated with or supported by Manaflow, the
company behind cmux.

- The build turns off cmux's analytics, crash reports and feature-flag requests, so none of
  them reach cmux.
- Sign-in, cloud machines and phone pairing are Manaflow services and are switched off.
- cmux's Computer Use, which lets agents click and type in other apps, is off until you turn
  it on.
- Its changes are kept small and separate so that upstream cmux can be merged regularly.

Details are in [How the fork differs from cmux](wheelhouse/docs/fork.md).

## License

Wheelhouse IDE is licensed like cmux: GPL-3.0-or-later for the app, CLI and packages, with the
server directories listed in [LICENSE](LICENSE) under the Business Source License 1.1. cmux is
copyright Manaflow, Inc. and its contributors; see
[THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md) for bundled dependencies. Monaco Editor is
MIT-licensed, copyright Microsoft Corporation.
