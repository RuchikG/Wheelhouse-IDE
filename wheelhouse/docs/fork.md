# How the fork differs from cmux

Wheelhouse IDE is cmux plus a small set of additions. This page covers what the fork changes
beyond its features: what it reports, what it is called, where its code lives, and how it stays
mergeable with upstream.

## Nothing reported to cmux

Wheelhouse IDE starts with "Send anonymous telemetry" off. In cmux that setting stops
usage analytics and crash reports but still asks cmux's feature-flag service for flag values every
30 minutes. In this fork it stops that request too: with telemetry off, flags use their built-in
defaults and local overrides. A fork has no business in cmux's analytics or crash reports, and its
bundle id still starts with cmux's, so cmux's own check for foreign builds would not have caught
it. Turn the setting back on in Settings to get upstream's behavior.

## Agent hooks on SSH hosts

When cmux attaches to a host with `cmux ssh`, it installs hooks in that host's Claude Code and
Codex settings (`~/.claude/settings.json`, `~/.codex/hooks.json`), one per agent event, so that
agents running there report their state to the sidebar. Wheelhouse IDE does not do this unless
you turn it on, because it changes files that every agent session on the host reads:

```sh
defaults write <bundle id> wheelhouse.remoteAgentHooks.enabled -bool true
```

The bundle id is `com.cmuxterm.app.staging.wheelhouse` for a downloaded build and
`com.cmuxterm.app.debug.<tag>` for a source build. The setting takes effect the next time a host
is attached. Which agents get hooks follows Settings → Integrations, as in cmux.

The hooks do nothing outside cmux and tmux sessions, with one exception seen with Claude Code
2.1: the hook on worktree creation makes `claude --worktree` fail on the host with "WorktreeCreate
hook failed". If you use worktrees there, remove the `WorktreeCreate` entry from the host's
`~/.claude/settings.json` after attaching, or leave the setting off. Turning the setting off
later stops new installs; it does not remove hooks already on a host.

Notifications from agents on SSH hosts do not need any of this; they use the small hook in
[`wheelhouse/remote-notify`](../remote-notify/README.md).

## Computer Use is off

cmux's Computer Use lets agents click and type in other apps through a helper app that needs
Accessibility and Screen Recording permission. Wheelhouse IDE does not install or start that
helper, and agents started in its terminals are not given the Computer Use tools, unless you
turn it on and restart the app:

```sh
defaults write <bundle id> wheelhouse.computerUse.enabled -bool true
```

The switch in Settings → Computer Use is cmux's own and is shared with an installed cmux through
`~/.config/cmux`; this setting applies to Wheelhouse IDE alone and leaves that one as it is.

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
| `Sources/WheelhouseDefaults.swift` | Preferences the app starts with on top of cmux's defaults |
| `Sources/WheelhouseProjects.swift` | The board from inside the app: the first-launch set-up and the New Project form, both run the bundled `proj` |
| `wheelhouse/release.sh`, `publish.sh` | Build the app that is handed to other people, and publish it as a GitHub release |
| `wheelhouse/update-key.swift` | The key that signs a release's updates: create it, print its public half, sign an archive |
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
key monitor, the built-in tab bar actions), for the one-line telemetry rule in
`Sources/FeatureFlags.swift`, for one line in `Sources/CmuxMain.swift` that registers the
fork's preferences, for the check in `Sources/RemoteTui/SSHTuiWorkspaceCoordinator.swift` that
makes agent hooks on SSH hosts opt-in, and for the two checks (`Sources/cmuxApp.swift`,
`Sources/TerminalSurfaceRuntimeWiring.swift`) that keep Computer Use off until asked for. The
project board adds: two lines in `AppDelegate.applicationDidFinishLaunching` (the first-launch
set-up and the Agents panel), the `wheelhouse.project.new` and `wheelhouse.proj.run` socket methods
(`Sources/TerminalController.swift` and its capabilities list), the File > New Project… item and the form's window id in
`Sources/cmuxApp.swift`, and two additions to the custom-sidebar package
(`Packages/macOS/CmuxSwiftRenderUI`): a `wheelhouse` global in `SidebarRuntime.js`, by which a
sidebar knows it runs in this app and has it run `proj`, and `light|dark` colour pairs in `RenderStyle.swift`.
The Agents panel (`Sources/WheelhouseAgents.swift`) adds the `wheelhouse.agents_panel.set` socket
method, one line each in `Sources/ContentView.swift` and `Sources/RightSidebarPanelView.swift` for
the title bar's Agents button and the mode bar left out while the panel is up, and two lines that put agents on SSH hosts into a
sidebar's `agents` and take out sessions that are no longer running, such as the ones restored
at launch (`Sources/RemoteTui/SSHTuiAgentStatusProjector.swift`,
`Sources/Workspace+CustomSidebarSnapshot.swift`). Session history, in the same file, adds the
`wheelhouse.session.open` socket method, a `sessions` list on a sidebar's workspaces (one field
in `CustomSidebarWorkspaceSnapshot`, two lines in `CustomSidebarDataContextBuilder`, one in
`Sources/Workspace+CustomSidebarSnapshot.swift`), the `wheelhouse` URL scheme in
`Resources/Info.plist` and one line in `Sources/AppDelegate+CmuxSSHURL.swift` that hands
`wheelhouse://session/…` links to it. Updates add one check to
`Packages/macOS/CmuxUpdater` (`UpdateController.isDevLikeBundle`): cmux keeps staging builds off
its update feed, and a release that carries a feed of its own
([Updates](building.md#updates)) is let through; and one line in the sidebar footer
(`Sources/ContentView.swift`) puts a single update button (`Sources/WheelhouseUpdateButton.swift`)
where cmux has its help menu, whose entries stay in the Help menu of the menu bar. Two
additions keep `claude` working in the app's terminals when it is installed as a shell alias
or outside the `PATH` (`Resources/shell-integration/cmux-zsh-integration.zsh`,
`Resources/bin/cmux-claude-wrapper`). The tab right-click menu is built by the Bonsplit submodule, which
this fork does not modify: the editor item is added to that menu when it opens. `upstream` is
`manaflow-ai/cmux`; merge it regularly. `README.md`, the generated web bundle and the icon images are the
files most likely to conflict; keep the fork's README, regenerate the bundle after a merge, and rerun
`wheelhouse/brand/icon/generate.sh` if upstream changes its icons.

The translated `README.*.md` files are upstream's and describe cmux, not this fork.
