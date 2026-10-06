# Project board

A kanban board of projects for the cmux sidebar, and `proj`, a small CLI that creates the lanes
and opens projects. Both use only cmux's own extension points (custom sidebars, workspace groups,
the CLI), so they work with this fork and with stock cmux.

- `sidebars/projects-board.js`: the board. Lanes are workspace groups; a card is a workspace.
- `cmd/proj`: creates the lane groups, opens a project as a workspace in its lane with its
  worktrees and agents, writes the projects' links into the board, and keeps lanes and project
  files in sync.
- `examples/`: a project file and a settings file to copy.

The design is described in the [repository README](../../README.md#project-board).

## Set up

Requires Go 1.24 or later and a running cmux.

```sh
cd wheelhouse/board
make install                      # builds bin/proj and links it into ~/.local/bin

mkdir -p ~/.config/wheelhouse/projects
cp examples/project.yaml ~/.config/wheelhouse/projects/my-project.yaml   # then edit it
cp examples/config.yaml ~/.config/wheelhouse/config.yaml                 # optional

proj init                         # lane groups + the board sidebar
proj open my-project
```

`proj init` writes the board to `~/.config/cmux/sidebars`. Pick `projects-board` from the sidebar
button's right-click menu, or run `cmux sidebar select projects-board`.

The installed board is a copy of `sidebars/projects-board.js` with each project's links written
into it, because a custom sidebar cannot read files. `proj open` and `proj adopt` rewrite it; run
`proj sync` after editing a project's links, the browser profile, or the board script itself.

`proj` drives whichever cmux `CMUX_BIN` names (default: `cmux` on `PATH`, else the installed app).
For Wheelhouse IDE, point it at the app's CLI:

```sh
CMUX_BIN=$PWD/../cli proj init
```

## Commands

```
proj init                  create the lane groups and install the board sidebar
proj sync                  write the projects' links into the installed board again
proj open <project>        create the project's worktrees and workspace (no-op when already open)
proj adopt <project>       turn the workspace you are in into the project's workspace
proj ls                    projects with their lane, workspace and checkouts
proj lane <project> <design|dev|review|release|done>
proj lane pull             copy lane moves made on the board back into the project files
proj wt                    every project checkout per repository, with conflicts
proj wt rm <project>       remove a project's worktrees (branches stay; refuses when dirty)
proj check                 validate the project files
```

## Projects

A project is one YAML file in `<home>/projects/`, where `<home>` is `~/.config/wheelhouse` or
`$WHEELHOUSE_HOME`. See [`examples/project.yaml`](examples/project.yaml). The file name is the
project's id on the command line; files starting with `_` are ignored.

| Key | Meaning |
| --- | --- |
| `name` | Card title and workspace name |
| `lane` | `design`, `dev`, `review`, `release` or `done` |
| `summary` | One line on the card |
| `dir` | Workspace directory (default: the first repository's checkout) |
| `repos` | Repositories: `path`, and optionally `branch`, `base`, `worktree` |
| `links` | Pages shown as chips on the card: `title`, `url`, and optionally `icon` (an [SF Symbol](https://developer.apple.com/sf-symbols/) name such as `calendar`) |
| `agents` | Terminals started with the workspace: `name`, `command`, optional `dir` |
| `location`, `host` | `remote` opens the project as a `cmux ssh <host>` workspace |

## Links

Each link is a chip on the project's card: an icon on every card, with the title on the selected
one. Clicking a chip selects the project and shows the link's browser tab, opening it first if
needed: in the pane of the project's other link tabs, or in a new pane on the right for the first
one, using the `browser_profile` setting. A chip is tinted while its tab is open. The chip's
right-click menu closes the tab or opens the page in your default browser.

Without an `icon`, the chip's icon follows the title: a ticket for titles with words such as
"ticket", "issue" or "bug", a branch for "pipeline", "build", "release" or "review", a document for
"doc", "design", "PRD" or "spec", and a link otherwise.

Chips need a cmux whose custom sidebars support `fixedSize` and `cursor` (Wheelhouse IDE does). On
an older cmux the board shows no chips, and the links are not opened for you.

The board recognizes a link's tab by its name, which is the link's `title`. Keep titles distinct
within a project, and do not rename those tabs. A title made only of digits is not supported.

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

## Notes

- A cmux workspace group is owned by an anchor workspace, so each lane carries one generated
  workspace named after the lane. The board hides it.
- Custom sidebars cannot reach the network or the filesystem, so the board shows only what cmux
  already knows about a workspace. Status from outside tools has to be pushed in through the cmux
  CLI (a workspace's description and progress).
- Run the tests with `make test`.
