# Project board

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
| The board itself | A [custom sidebar](../../docs/custom-sidebars.md) script |

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
- **Drag to move.** Drag a card to another lane, or to another place in its own; the name of the
  lane it would land in is tinted while you drag, and Escape gives up. The lane is saved in the
  project file. Cards that wait on you stay first in their lane wherever they are dropped.
- **Agents view.** The switch at the top of the board turns it into a list of every agent in
  every project, grouped Needs you, Working and Idle, with the longest wait first. A row shows
  the agent's tab name, its project, its task (the last prompt typed in its tab), how many
  sub-agents it is running and for how long it has been in that state; a click goes to that
  agent. An agent that has finished its turn moves to Needs you after about a minute, when its
  idle reminder fires. The switch carries the number
  of agents waiting on you.
- **Agents panel.** While a project is selected, a panel on the right lists its agents with
  their state, task, sub-agents and folder, and under them the project's earlier sessions. It
  shows nothing else: the bar with the right sidebar's other modes is left out while it is up,
  and those stay reachable by their shortcuts. The button at its top, or hiding the right
  sidebar (View > Toggle Right Sidebar), collapses it to an **Agents** button at the right end
  of the title bar, whose dot is orange while an agent of the project waits on you and blue
  while one works; the button opens the panel again. The panel goes away when you select a
  workspace that is not a project and never replaces another right sidebar that is open. This
  part needs Wheelhouse IDE; `defaults write <bundle id> wheelhouse.agentsPanel.enabled -bool
  false` turns it off.
- **Session history.** Wheelhouse IDE keeps a record of every agent session started in a
  project's terminals: the harness, the session's id, its first prompt, the folder, when it
  started and when it ended. Sub-agents are not separate records, and a session that is resumed
  stays the same record. The records are in `<home>/sessions/<project>.json`, next to the
  project files, at most 500 ended sessions per project. In the panel an earlier session shows
  its harness, first prompt, start time and length. **Resume** opens a new tab in the project
  and types the harness's resume command there; the link button copies
  `wheelhouse://session/<project>/<session>`, which opens the project and resumes that session
  from anywhere on the Mac (`open wheelhouse://…`), or goes to its tab while it still runs.
  Sessions on SSH hosts are listed with the host's name and without Resume: the host reports
  that an agent runs, not which session.

  Which sessions are recorded depends on what the app can tell apart in a terminal. Claude Code
  and Codex are built in, as is every agent cmux itself recognises. Any other harness is
  described in `<home>/harnesses.json`, a list in which an entry with the id of a built-in one
  replaces it:

  ```json
  [
    {"id": "mycli", "name": "My CLI", "process": ["mycli"],
     "sessionFiles": "~/.mycli/sessions", "resume": "mycli resume {id}"},
    {"id": "kit", "name": "Kit", "launcher": ["kit"], "wraps": "claude",
     "resume": "kit claude --resume {id}"}
  ]
  ```

  `process` names the agent's program. Its session id comes from `pidFile`, a JSON file with
  `{pid}` in its path and the id under `sessionId` (Claude Code:
  `~/.claude/sessions/{pid}.json`), or from `sessionFiles`, a folder where the agent writes one
  JSON-lines file per session, named with the id last and naming the agent's folder as `cwd`
  in its first line (Codex: `~/.codex/sessions`). `transcript` is where the first prompt is
  read when there is no session file. An entry with `launcher` and `wraps` is a tool that
  starts another harness: a session started through it carries its name and is resumed with
  its command. Only the name a process was called by and its first argument are looked at,
  and nothing of a command line is stored.
- **Links are chips on the card,** not tabs that stay open. A project carries one link of each
  kind from a short fixed list (by default a PRD, a tech solution, a tech design, a tracker and a
  pipeline; the list is a setting), and each shows as a named chip on its card. Clicking a chip
  opens the page as a browser tab in the project's workspace, or shows the tab if it is already
  open; an open link's chip is tinted. Close the tab when you are done, from the tab or from the
  chip's right-click menu, and the chip stays for next time.
- **Links are added where you are.** Right-click a card, pick the kind under Links and paste the
  address into the field that appears on the card; a chip's own menu changes or removes its
  link. From a terminal or an agent, `proj link <kind> <url>` does the same for the project of
  the workspace it runs in, and a Claude Code skill tells the agent so.
- **Beyond links, the board only reads state and jumps.** Work happens in the project's workspace:
  in its terminals and agents, in the real web tools opened as browser tabs, and in the editor.
  Nothing is re-implemented on the board.
- **Workspaces that are not projects** are listed under "Not on the board" and can be added to a
  lane from there.
- **Nothing to set up.** The first launch creates the lanes, shows the board and adds an example
  project with a folder of its own, so there is a card to click before you have made one.
- **Projects are added from the board.** The + at the top opens a short form: a name and a
  folder, and optionally the lane, a summary and a command for the first terminal. A project
  whose workspace was closed stays listed under Closed and opens again with a click.
- **A project is one small file:** name, lane, summary, repositories with their branch, links
  for the card, and agents to start. The form writes it; edit it by hand for the rest. Opening
  a project creates its workspace in the right lane, starts the agents, and gives it its own git
  worktree per repository, so two projects on the same repository never share a checkout.
- **Readable in light and dark.** The board has a palette for each appearance and follows the
  app's theme.
- **Remote projects** are ordinary cmux SSH workspaces; the card carries a badge.

The board is built on cmux's own extension points (custom sidebars, workspace groups and the
CLI), so it also works with stock cmux. Wheelhouse IDE adds these around it: the first launch
runs the set-up, the New Project form, sidebar colours given per appearance, the Agents panel,
and agents on SSH hosts in the data a sidebar reads. The sidebar scripts and `proj`, the small
CLI behind the board, are in
[`wheelhouse/board`](../board/README.md).
