# How the fork differs from cmux

Wheelhouse IDE is cmux plus a small set of additions. This page covers what the fork changes
beyond its features: what it reports, what it is called, where its code lives, and how it stays
mergeable with upstream.

## Nothing reported to cmux

`wheelhouse/defaults.sh` also turns off "Send anonymous telemetry". In cmux that setting stops
usage analytics and crash reports but still asks cmux's feature-flag service for flag values every
30 minutes. In this fork it stops that request too: with telemetry off, flags use their built-in
defaults and local overrides. A fork has no business in cmux's analytics or crash reports, and its
bundle id still starts with cmux's, so cmux's own check for foreign builds would not have caught
it. Turn the setting back on in Settings to get upstream's behavior.

## Naming and icon

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
files most likely to conflict; keep the fork's README, regenerate the bundle after a merge, and rerun
`wheelhouse/brand/icon/generate.sh` if upstream changes its icons.

The translated `README.*.md` files are upstream's and describe cmux, not this fork.
