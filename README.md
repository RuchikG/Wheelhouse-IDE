# Wheelhouse

Wheelhouse is a fork of [cmux](https://github.com/manaflow-ai/cmux), the Ghostty-based macOS
terminal for AI coding agents. It adds a built-in code editor, with the goal of running a whole
project from one window: terminals, agents, browser tabs and code.

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
- Follows the panel's light or dark colors and the existing `fileEditor.*` settings (word wrap,
  line numbers, indent guides, current-line highlight, tab width).

Not there yet:

- Language features (completion, go to definition, diagnostics). These come with LSP support.
- Remote files are read-only, as in cmux.
- Markdown source editing still uses the native editor.
- Where an app shortcut and an editor shortcut overlap, the app shortcut wins.

To go back to the native editor:

```sh
defaults write <bundle id> wheelhouse.codeEditor.enabled -bool false
```

The bundle id of a tagged dev build is `com.cmuxterm.app.debug.<tag>`.

### Roadmap

| Step | State |
| --- | --- |
| Editor in the file panel | Done |
| LSP: completion, definitions, hover, diagnostics (gopls first) | Next |
| Remote workspaces: edit and save files over SSH, language server on the remote host | Planned |
| Project board: a sidebar of projects in lanes (Design, Dev, Review & Test, Release, Done) | Prototype outside this repository, built on cmux's custom sidebars |

## Build

Requirements: macOS 14 or later, Xcode 26 or later with the Metal toolchain component, Zig and
Rust. Rebuilding the web bundle also needs [bun](https://bun.sh).

```sh
git clone https://github.com/RuchikG/Wheelhouse-IDE.git
cd Wheelhouse-IDE
./scripts/setup.sh
CMUX_DEV_BACKEND_MODE=local ./scripts/reload.sh --tag wheelhouse
```

The first build takes around 25 minutes. `reload.sh` prints the path of the built app
(`cmux DEV wheelhouse.app`); open it from Finder or with `open`. A tagged build has its own bundle
id and socket, so it runs next to an installed cmux without touching it. Drive it from a terminal
with:

```sh
CMUX_TAG=wheelhouse scripts/cmux-debug-cli.sh open path/to/file.go
```

`CMUX_DEV_BACKEND_MODE=local` keeps the build off the cmux cloud backend. Sign-in, cloud machines
and mobile pairing are upstream features that need Manaflow's services and are not part of what
this fork is for.

## Where the fork's code is

| Path | What |
| --- | --- |
| `Packages/macOS/WheelhouseCodeEditor` | Swift package: the web view host, a private URL scheme that serves the bundled editor, the bridge to the page, unit tests |
| `Sources/Panels/FilePreviewCodeEditor.swift` | Adapter between the file panel and the editor |
| `webviews/src/code-editor`, `webviews/src/surfaces/codeEditorSurface.ts` | The editor page |
| `Resources/markdown-viewer/webviews-app` | Built web bundle (generated; do not edit) |

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
files, and upstream files are touched only where the editor hooks in. `upstream` is
`manaflow-ai/cmux`; merge it regularly. `README.md` and the generated web bundle are the files most
likely to conflict; keep this README, and regenerate the bundle after a merge.

The translated `README.*.md` files are upstream's and describe cmux, not this fork.

## License

Wheelhouse is licensed like cmux: GPL-3.0-or-later for the app, CLI and packages, with the
server directories listed in [LICENSE](LICENSE) under the Business Source License 1.1. cmux is
copyright Manaflow, Inc. and its contributors; see [THIRD_PARTY_LICENSES.md](THIRD_PARTY_LICENSES.md)
for bundled dependencies. Monaco Editor is MIT-licensed, copyright Microsoft Corporation.
