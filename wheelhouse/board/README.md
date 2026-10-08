# Project board

A kanban board of projects for the cmux sidebar, and `proj`, a small CLI that creates the lanes
and opens projects. Both use only cmux's own extension points (custom sidebars, workspace groups,
the CLI), so they work with this fork and with stock cmux.

- `sidebars/projects-board.js`: the board. Lanes are workspace groups; a card is a workspace.
- `sidebars/project-agents.js`: the agents of the selected project and, in Wheelhouse IDE, its
  earlier sessions. Wheelhouse IDE installs it and shows it on the right while a project is
  selected; in cmux, copy it to `~/.config/cmux/sidebars/` and run
  `cmux right-sidebar set custom project-agents`.
- `cmd/proj`: creates the lane groups, adds projects, opens a project as a workspace in its lane
  with its worktrees and agents, writes the projects' links into the board, and keeps lanes and
  project files in sync.
- `skills/project-links`: a Claude Code skill that lets an agent keep a project's links.
- `examples/`: a project file with every setting, a settings file, and the example project's
  read-me.

The design is described in [Project board](../docs/board.md).

## Set up

**In Wheelhouse IDE there is nothing to set up.** The first time the app opens it creates the
lanes, shows the board as the sidebar and adds an example project to look around in. `proj` is
part of the app and on the `PATH` of its terminals.

That first launch is `proj init`, which you can also run yourself at any time; it only adds what
is missing:

```sh
proj init        # the lanes, the board as the sidebar and, the first time, the example project
```

It keeps your projects in `~/.config/wheelhouse/projects` and the example's folder next to it.
Settings are optional; copy [`examples/config.yaml`](examples/config.yaml) to
`~/.config/wheelhouse/config.yaml` to change them.

To use the board with stock cmux, or to work on `proj` itself, build it from this folder
(Go 1.24 or later) and run `proj init` once:

```sh
cd wheelhouse/board
make install                      # builds bin/proj and links it into ~/.local/bin
make install-skill                # optional: links the project-links skill into ~/.claude/skills
```

`proj init` writes the board to `~/.config/cmux/sidebars` and selects it. To switch back and
forth, use the sidebar button's right-click menu.

## Adding a project

- **In Wheelhouse IDE:** click the **+** at the top of the board, or choose File > New Project….
  Give the project a name and pick its folder; the lane, a one-line summary and a command for its
  first terminal (an agent, for example) are optional. The project opens in its lane.
- **From a terminal:** `proj new "Checkout redesign" --dir ~/code/checkout`, with `--lane`,
  `--summary` and `--agent <command>` for the rest. This also works with stock cmux.

Either way the project is one small file in `~/.config/wheelhouse/projects`, which you can edit
for the settings the form does not ask about (see [Projects](#projects)).

A project whose workspace you closed is listed under **Closed** at the bottom of the board in
Wheelhouse IDE; click it to open it again. From a terminal that is `proj open <project>`.

To take a closed project off the board, right-click it under **Closed** and choose **Remove from
board**, or run `proj rm <project>`. Its file moves to `~/.config/wheelhouse/archive`, together
with the record of its agent sessions (`<project>.sessions.json`), and nothing reads that
folder. Worktrees stay where they are; run `proj wt rm <project>` first to remove them. To bring
a project back, move its file into `projects` again, and its sessions file to
`sessions/<project>.json`.

The installed board is a copy of `sidebars/projects-board.js` with each project's links written
into it, because a custom sidebar cannot read files. `proj open`, `proj adopt` and `proj link`
rewrite it; run `proj sync` after editing a project file's links by hand, the settings, or the
board script itself.

`proj` drives whichever cmux `CMUX_BIN` names (default: `cmux` on `PATH`, else the installed app).
Inside a Wheelhouse IDE terminal that is the app itself. From any other terminal, point it at a
source build's CLI:

```sh
CMUX_BIN=$PWD/../cli proj init
```

## Commands

```
proj init                  create the lanes, install the board and show it as the sidebar;
                           the first time, also add the example project
proj new <name> [--dir <folder>] [--lane <lane>] [--summary <text>] [--agent <command>]
                           add a project and open it
proj example               add the example project, or open it when it is there
proj sync                  write the projects' links into the installed board again
proj open <project>        create the project's worktrees and workspace (no-op when already open)
proj adopt <project>       turn the workspace you are in into the project's workspace
proj ls                    projects with their lane, workspace and checkouts
proj lane <project> <design|dev|review|release|done>
proj lane pull             copy lane moves made on the board back into the project files
proj rm <project>          take a closed project off the board; its file moves to the archive
proj link [<project>]      a project's links, one line per link kind
proj link [<project>] <kind> <url>
                           set a project's link of that kind
proj link rm [<project>] <kind>
                           remove it
proj wt                    every project checkout per repository, with conflicts
proj wt rm <project>       remove a project's worktrees (branches stay; refuses when dirty)
proj check                 validate the project files
```

## Projects

A project is one YAML file in `<home>/projects/`, where `<home>` is `~/.config/wheelhouse` or
`$WHEELHOUSE_HOME`. The New Project form and `proj new` write it for you; every setting is shown
in [`examples/project.yaml`](examples/project.yaml), which `proj init` also leaves in that folder
as `_example.yaml`. The file name is the project's id on the command line; files starting with
`_` are ignored.

| Key | Meaning |
| --- | --- |
| `name` | Card title and workspace name |
| `lane` | `design`, `dev`, `review`, `release` or `done` |
| `summary` | One line on the card |
| `dir` | Workspace directory (default: the first repository's checkout) |
| `repos` | Repositories: `path`, and optionally `branch`, `base`, `worktree` |
| `links` | Pages shown as chips on the card: `title` (a link kind), `url`, and optionally `icon` to replace the kind's |
| `agents` | Terminals started with the workspace: `name`, `command`, optional `dir` |
| `location`, `host` | `remote` opens the project as a `cmux ssh <host>` workspace |

## Links

A project can carry one link of each **link kind**. The kinds are the `link_kinds` setting: by
default PRD, Tech Solution, Tech Design, Tracker and Pipeline. In a project file a link's `title`
names its kind; case, spaces and punctuation do not matter, so `tech design` and `tech-design` are
the Tech Design kind. A link whose title is no kind stays in the file and off the board, and
`proj check` says so.

Each link is a chip on the project's card, named after its kind and shown in the order of the
kinds. Clicking a chip selects the project and shows the link's browser tab, opening it first if
needed: in the pane of the project's other link tabs, or in a new pane on the right for the first
one, using the `browser_profile` setting. A chip is tinted while its tab is open. The chip's
right-click menu closes the tab or opens the page in your default browser.

Link tabs have their own cookies, so a page that needs a sign-in asks for it again. In Wheelhouse
IDE the key button at the top of the board (also in a chip's right-click menu) copies the sign-ins
from Chrome or another browser on this Mac into the profile the link tabs use: pick the browser
and its profile, then Import. For Chrome, macOS asks once for access to "Chrome Safe Storage" in
your keychain, which holds the key Chrome encrypts its cookies with. Reload a tab that was already
open. Sign-ins expire as they do in the browser; import again to refresh them. The same import is
at View > Import Browser Data… and, from a terminal, `cmux browser import --from chrome`.

To add, change or remove a link:

- **On the board:** right-click the card, open **Links** and pick a kind. A field appears on the
  card; paste the address and press Return (Escape cancels). A chip's right-click menu has
  **Change link…** and **Remove link**.
- **From a terminal or an agent:** `proj link <kind> <url>` and `proj link rm <kind>`. Inside a
  workspace that `proj open` created, the project is known; elsewhere name it first
  (`proj link my-project prd https://…`). `make install-skill` gives Claude Code a skill that
  uses these commands when you ask it to link a page to the project.
- **By hand:** edit `links:` in the project file, then run `proj sync`.

`proj link` edits the project file in place and keeps its comments and layout. It needs `links:`
written as a list with one entry per line.

A custom sidebar cannot write files, so the board saves a link by running `proj link`. Wheelhouse
IDE runs it out of sight and shows an alert with the reason if the link could not be changed. In
cmux the command runs in a workspace of its own named "Saving link", which closes by itself after
about a second and stays open with the reason on a failure.

Chips and the Links menu need a cmux whose custom sidebars support `fixedSize` and `cursor`
(Wheelhouse IDE does). On an older cmux the board shows neither, and the links are not opened for
you.

The board recognizes a link's tab by its name, which is the kind's title, so do not rename those
tabs. A kind title made only of digits is not supported.

## Worktrees

Two projects on the same repository must not share a checkout, so a repository entry with a
`branch` gets its own git worktree at `<worktrees>/<project>/<repo>`. Your main checkouts are
never switched or modified.

- `proj open` creates the worktree from the local branch, else `origin/<branch>`, else a new
  branch from `base` (default: the remote's default branch, as last fetched).
- Git allows a branch in one checkout only. If the branch is already checked out somewhere,
  `proj open` stops and says where; it never forces. `worktree: false` uses the main checkout.
- `proj check` and `proj wt` report two projects claiming the same branch (an error) or sharing a
  main checkout (a warning).
- Worktrees on remote hosts are not managed yet; the path is used as it is.

## Settings

`<home>/config.yaml`, every key optional; see [`examples/config.yaml`](examples/config.yaml). A
`WHEELHOUSE_*` environment variable overrides the file.

| Key | Default | Variable |
| --- | --- | --- |
| `worktrees` | `<home>/worktrees` | `WHEELHOUSE_WORKTREES` |
| `browser_profile` | cmux's default profile | `WHEELHOUSE_BROWSER_PROFILE` |
| `agent_dir` | the workspace directory | `WHEELHOUSE_AGENT_DIR` |
| `remote_host` | none | `WHEELHOUSE_REMOTE_HOST` |
| `remote_agent_dir` | the workspace directory | `WHEELHOUSE_REMOTE_AGENT_DIR` |
| `link_kinds` | PRD, Tech Solution, Tech Design, Tracker, Pipeline | none |

`link_kinds` is a list of `title` and optional `icon`, an
[SF Symbol](https://developer.apple.com/sf-symbols/) name such as `ticket`. Without an icon, one
is chosen from the title: a ticket for words such as "ticket", "issue" or "bug", a branch for
"pipeline", "build", "release" or "review", a document for "doc", "design", "PRD" or "spec", and a
link otherwise.

## Wheelhouse IDE and stock cmux

The board is one script for both. Wheelhouse IDE tells its sidebars that it is Wheelhouse IDE,
and there the board also shows what needs the app: the **+** and the "No projects open" card
(the New Project form), the **Closed** list, dragging a card to another lane, the button that
imports sign-ins, and a palette for each appearance (the board's colours are given as a light and
a dark one, which only Wheelhouse IDE's sidebars understand). In stock cmux the board keeps one
palette, cards change lane from their right-click menu and projects are added with `proj new`.

## Notes

- A cmux workspace group is owned by an anchor workspace, so each lane carries one generated
  workspace named after the lane. The board hides it.
- cmux removes such a group when its last other workspace leaves, unless the group is pinned,
  so `proj` pins the lanes: an emptied lane stays. Any `proj` command that needs the lanes puts
  back a missing one and pins one that is not; in Wheelhouse IDE a missing lane on the board
  says so and one click restores them.
- Moving a card on the board moves its workspace. In Wheelhouse IDE the project file is updated
  too; with stock cmux run `proj lane pull` to copy lane moves back into the project files.
- Custom sidebars cannot reach the network or the filesystem, so the board shows only what cmux
  already knows about a workspace. Status from outside tools has to be pushed in through the cmux
  CLI (a workspace's description and progress).
- Run the tests with `make test`.
