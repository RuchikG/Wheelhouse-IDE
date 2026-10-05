package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"strings"
	"text/tabwriter"
	"time"
)

const usage = `proj - project workspaces on cmux

  proj init                  create the lane groups, the browser profile and install the board sidebar
  proj ls                    list projects with their lane, workspace and checkouts
  proj open <project> [--focus]
                             create the project's worktrees and workspace (no-op when already open)
  proj adopt <project> [workspace]
                             turn an existing workspace (default: the current one) into the project's workspace
  proj lane <project> <lane> move a project to a lane (manifest and board)
  proj lane pull             copy lane moves made on the board back into the manifests
  proj wt                    show every project checkout per repo, with conflicts
  proj wt rm <project>       remove a project's worktrees (branches stay; refuses when dirty)
  proj check                 validate the manifests

Settings live in <home>/config.yaml (all optional); a WHEELHOUSE_* variable overrides the file:
  WHEELHOUSE_HOME              directory holding projects/ and config.yaml (default: ~/.config/wheelhouse)
  worktrees                    where worktrees go (default: <home>/worktrees)        WHEELHOUSE_WORKTREES
  browser_profile              cmux browser profile for project tabs                 WHEELHOUSE_BROWSER_PROFILE
  agent_dir                    where agents start (default: the workspace directory) WHEELHOUSE_AGENT_DIR
  remote_host                  ssh destination for remote projects without a host    WHEELHOUSE_REMOTE_HOST
  remote_agent_dir             where agents start on the remote host                 WHEELHOUSE_REMOTE_AGENT_DIR
  CMUX_BIN                     cmux CLI to drive (default: cmux on PATH, else the installed app's)
`

func main() {
	if len(os.Args) < 2 || os.Args[1] == "-h" || os.Args[1] == "--help" || os.Args[1] == "help" {
		fmt.Print(usage)
		return
	}
	if err := run(os.Args[1], os.Args[2:]); err != nil {
		fmt.Fprintln(os.Stderr, "proj:", err)
		os.Exit(1)
	}
}

func run(cmd string, args []string) error {
	cfg, err := loadConfig()
	if err != nil {
		return err
	}
	all, err := loadAll(filepath.Join(cfg.home, "projects"))
	if err != nil {
		return err
	}
	switch cmd {
	case "init":
		return cmdInit(cfg)
	case "ls":
		return cmdLs(cfg, all)
	case "check":
		return cmdCheck(all)
	case "open":
		return cmdOpen(cfg, all, args)
	case "adopt":
		return cmdAdopt(cfg, all, args)
	case "lane":
		return cmdLane(all, args)
	case "wt":
		return cmdWt(cfg, all, args)
	}
	return fmt.Errorf("unknown command %q\n\n%s", cmd, usage)
}

func cmdInit(cfg *config) error {
	if _, err := ensureLanes(); err != nil {
		return err
	}
	fmt.Println("lanes ready:", laneLabels())
	if err := ensureProfile(cfg.profile); err != nil {
		return err
	}

	src, err := sidebarSource()
	if err != nil {
		return err
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return err
	}
	dst := filepath.Join(home, ".config", "cmux", "sidebars", "projects-board.js")
	if err := os.MkdirAll(filepath.Dir(dst), 0o755); err != nil {
		return err
	}
	switch target, err := os.Readlink(dst); {
	case err == nil && target == src:
	case errors.Is(err, os.ErrNotExist):
		if err := os.Symlink(src, dst); err != nil {
			return err
		}
	default:
		return fmt.Errorf("%s already exists and is not our symlink; move it away and rerun", dst)
	}
	fmt.Println("board installed:", dst)
	fmt.Println("show it with the sidebar button's right-click menu, or: cmux sidebar open projects-board")
	return nil
}

func laneLabels() string {
	labels := make([]string, len(lanes))
	for i, l := range lanes {
		labels[i] = l.Label
	}
	return strings.Join(labels, " → ")
}

func ensureProfile(name string) error {
	if name == "" {
		return nil
	}
	out, err := cmux("browser", "profiles", "list")
	if err != nil {
		return err
	}
	for line := range strings.SplitSeq(out, "\n") {
		if fields := strings.Split(line, "\t"); fields[0] == name {
			return nil
		}
	}
	if _, err := cmux("browser", "profiles", "add", name); err != nil {
		return err
	}
	fmt.Printf("browser profile %q created; sign in once in a project tab\n", name)
	return nil
}

func cmdCheck(all []*Manifest) error {
	issues := validate(all)
	for _, i := range issues {
		fmt.Println(i)
	}
	if countErrors(issues) > 0 {
		return fmt.Errorf("%d manifest error(s)", countErrors(issues))
	}
	fmt.Printf("%d project(s) ok\n", len(all))
	return nil
}

func countErrors(issues []issue) int {
	n := 0
	for _, i := range issues {
		if !i.Warn {
			n++
		}
	}
	return n
}

func cmdLs(cfg *config, all []*Manifest) error {
	b, err := loadBoard()
	if err != nil {
		return err
	}
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "PROJECT\tLANE\tWHERE\tWORKSPACE\tCHECKOUTS")
	for _, m := range all {
		lane, wsRef := m.Lane, "-"
		if ws := b.workspaceFor(m); ws != nil {
			wsRef = ws.Ref
			if live := b.liveLane(ws.Ref); live != "" && live != m.Lane {
				lane = fmt.Sprintf("%s (manifest: %s)", live, m.Lane)
			}
		}
		var repos []string
		for _, r := range m.Repos {
			label := filepath.Base(r.Path)
			if r.Branch != "" {
				label += "@" + r.Branch
			}
			if m.Location == locLocal {
				label += " [" + inspectRepo(cfg.worktrees, m.Slug, r).State + "]"
			}
			repos = append(repos, label)
		}
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", m.Slug, lane, m.Location, wsRef, strings.Join(repos, ", "))
	}
	return tw.Flush()
}

func cmdOpen(cfg *config, all []*Manifest, args []string) error {
	var slug string
	focus := false
	for _, a := range args {
		switch {
		case a == "--focus":
			focus = true
		case slug == "":
			slug = a
		default:
			return fmt.Errorf("unexpected argument %q", a)
		}
	}
	if slug == "" {
		return errors.New("usage: proj open <project> [--focus]")
	}
	m, err := findManifest(all, slug)
	if err != nil {
		return err
	}
	blocked := false
	for _, i := range validate(all) {
		if i.Slug == m.Slug {
			fmt.Println(i)
			blocked = blocked || !i.Warn
		}
	}
	if blocked {
		return errors.New("fix the manifest first")
	}

	b, err := loadBoard()
	if err != nil {
		return err
	}
	if ws := b.workspaceFor(m); ws != nil {
		fmt.Printf("%s is already open (%s)\n", m.Name, ws.Ref)
		if focus {
			_, err = cmux("workspace", "select", ws.Ref)
		}
		return err
	}

	groups, err := ensureLanes()
	if err != nil {
		return err
	}
	if err := ensureProfile(cfg.profile); err != nil {
		return err
	}

	cwd := expandHome(m.Dir)
	var checkouts []string
	if m.Location == locRemote {
		cwd = m.Dir
		if cwd == "" && len(m.Repos) > 0 {
			cwd = m.Repos[0].Path
		}
	} else {
		for _, r := range m.Repos {
			dir, note, err := ensureCheckout(cfg.worktrees, m.Slug, r)
			if err != nil {
				return fmt.Errorf("repo %s: %w", r.Path, err)
			}
			fmt.Printf("checkout  %s", dir)
			if note != "" {
				fmt.Printf("  (%s)", note)
			}
			fmt.Println()
			checkouts = append(checkouts, dir)
			if cwd == "" {
				cwd = dir
			}
		}
		if cwd == "" {
			cwd, _ = os.UserHomeDir()
		}
	}

	var wsRef string
	if m.Location == locRemote {
		wsRef, err = openRemoteWorkspace(cfg, m, cwd, groups[m.Lane])
	} else {
		wsRef, err = openLocalWorkspace(cfg, m, cwd, checkouts, groups[m.Lane])
	}
	if err != nil {
		return err
	}
	fmt.Printf("workspace %s  %s  [%s]\n", wsRef, m.Name, m.Lane)

	if err := openLinks(cfg, m, wsRef); err != nil {
		return err
	}
	if focus {
		_, err = cmux("workspace", "select", wsRef)
	}
	return err
}

// cmdAdopt puts a workspace that already exists on the board. It keeps the workspace's
// terminals as they are and only adds the project's name, summary, lane and tabs.
func cmdAdopt(cfg *config, all []*Manifest, args []string) error {
	if len(args) < 1 || len(args) > 2 {
		return errors.New("usage: proj adopt <project> [workspace]")
	}
	m, err := findManifest(all, args[0])
	if err != nil {
		return err
	}
	target := os.Getenv("CMUX_WORKSPACE_ID")
	if len(args) == 2 {
		target = args[1]
	}
	if target == "" {
		return errors.New("not inside a cmux workspace; pass the workspace ref")
	}
	b, err := loadBoard()
	if err != nil {
		return err
	}
	if ws := b.workspaceFor(m); ws != nil {
		return fmt.Errorf("%s already has a workspace (%s)", m.Name, ws.Ref)
	}
	groups, err := ensureLanes()
	if err != nil {
		return err
	}
	if _, err := cmux("rename-workspace", "--workspace", target, m.Name); err != nil {
		return err
	}
	if m.Summary != "" {
		if _, err := cmux("workspace-action", "--workspace", target, "--action", "set-description", "--description", m.Summary); err != nil {
			return err
		}
	}
	if _, err := cmux("workspace-group", "add", "--group", groups[m.Lane].Ref, "--workspace", target); err != nil {
		return err
	}
	fmt.Printf("adopted   %s  [%s]\n", m.Name, m.Lane)
	if len(m.Links) == 0 {
		return nil
	}
	if err := ensureProfile(cfg.profile); err != nil {
		return err
	}
	return openLinks(cfg, m, target)
}

// agentDir is where an agent starts: its own dir, else the configured shared directory, else
// the workspace directory.
func agentDir(cfg *config, a Agent, cwd string) string {
	if a.Dir != "" {
		return expandHome(a.Dir)
	}
	if cfg.agentDir != "" {
		return cfg.agentDir
	}
	return cwd
}

func agentCommand(cfg *config, a Agent, cwd string) string {
	dir := agentDir(cfg, a, cwd)
	if dir == cwd {
		return a.Command
	}
	return "cd " + shellQuote(dir) + " && " + a.Command
}

func shellQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func openLocalWorkspace(cfg *config, m *Manifest, cwd string, checkouts []string, lane group) (string, error) {
	args := []string{
		"new-workspace", "--name", m.Name, "--cwd", cwd, "--focus", "false",
		"--group", lane.Ref, "--group-placement", "end",
		"--env", "IDE_PROJECT=" + m.Slug, "--env", "IDE_PROJECT_MANIFEST=" + m.File,
		"--env", "IDE_PROJECT_CHECKOUTS=" + strings.Join(checkouts, ":"),
	}
	if m.Summary != "" {
		args = append(args, "--description", m.Summary)
	}
	if len(m.Agents) > 0 && m.Agents[0].Command != "" {
		args = append(args, "--command", agentCommand(cfg, m.Agents[0], cwd))
	}
	out, err := cmux(args...)
	if err != nil {
		return "", err
	}
	fields := strings.Fields(out)
	if len(fields) == 0 || !strings.HasPrefix(fields[len(fields)-1], "workspace:") {
		return "", fmt.Errorf("cmux new-workspace: unexpected output: %s", out)
	}
	wsRef := fields[len(fields)-1]

	if len(m.Agents) > 0 && m.Agents[0].Name != "" {
		if _, err := cmux("rename-tab", "--workspace", wsRef, m.Agents[0].Name); err != nil {
			return "", err
		}
	}
	if len(m.Agents) > 1 {
		pane, err := firstPane(wsRef)
		if err != nil {
			return "", err
		}
		for _, a := range m.Agents[1:] {
			surfaceArgs := []string{"new-surface", "--type", "terminal", "--workspace", wsRef, "--pane", pane, "--working-directory", agentDir(cfg, a, cwd), "--focus", "false"}
			if a.Command != "" {
				surfaceArgs = append(surfaceArgs, "--command", a.Command)
			}
			var c created
			if err := cmuxJSON(&c, surfaceArgs...); err != nil {
				return "", err
			}
			if a.Name != "" {
				if _, err := cmux("rename-tab", "--workspace", wsRef, "--surface", c.SurfaceRef, a.Name); err != nil {
					return "", err
				}
			}
		}
	}
	return wsRef, nil
}

func openRemoteWorkspace(cfg *config, m *Manifest, cwd string, lane group) (string, error) {
	host := m.Host
	if host == "" {
		host = cfg.remoteHost
	}
	if host == "" {
		return "", errors.New("remote project without a host: set host in the manifest or remote_host in config.yaml")
	}
	args := []string{"ssh", host, "--name", m.Name, "--no-focus"}
	var steps []string
	if len(m.Agents) > 0 && m.Agents[0].Command != "" {
		dir := m.Agents[0].Dir
		if dir == "" {
			dir = cfg.remoteAgentDir
		}
		if dir == "" {
			dir = cwd
		}
		// Unquoted so the remote shell expands a leading ~.
		if dir != "" {
			steps = append(steps, "cd "+dir)
		}
		steps = append(steps, m.Agents[0].Command)
	} else if cwd != "" {
		steps = append(steps, "cd "+cwd)
	}
	if len(steps) > 0 {
		args = append(args, "--command", strings.Join(steps, " && "))
	}
	if _, err := cmux(args...); err != nil {
		return "", err
	}
	if len(m.Agents) > 1 {
		fmt.Println("warn  only the first agent is started on a remote host; add the others by hand for now")
	}

	var ws *workspace
	for attempt := 0; attempt < 20 && ws == nil; attempt++ {
		b, err := loadBoard()
		if err != nil {
			return "", err
		}
		if ws = b.workspaceFor(m); ws == nil {
			time.Sleep(250 * time.Millisecond)
		}
	}
	if ws == nil {
		return "", fmt.Errorf("cmux ssh %s did not produce a workspace named %q", host, m.Name)
	}
	if m.Summary != "" {
		if _, err := cmux("workspace-action", "--workspace", ws.Ref, "--action", "set-description", "--description", m.Summary); err != nil {
			return "", err
		}
	}
	if _, err := cmux("workspace-group", "add", "--group", lane.Ref, "--workspace", ws.Ref); err != nil {
		return "", err
	}
	return ws.Ref, nil
}

// openLinks puts every link in one browser pane to the right of the terminal, one tab each.
func openLinks(cfg *config, m *Manifest, wsRef string) error {
	var pane string
	for _, l := range m.Links {
		var c created
		var err error
		if pane == "" {
			args := []string{"new-pane", "--type", "browser", "--direction", "right", "--workspace", wsRef, "--url", l.URL, "--focus", "false"}
			if cfg.profile != "" {
				args = append(args, "--profile", cfg.profile)
			}
			err = cmuxJSON(&c, args...)
			pane = c.PaneRef
		} else {
			err = cmuxJSON(&c, "new-surface", "--type", "browser", "--workspace", wsRef, "--pane", pane, "--url", l.URL, "--focus", "false")
		}
		if err != nil {
			return err
		}
		if l.Title != "" {
			if _, err := cmux("rename-tab", "--workspace", wsRef, "--surface", c.SurfaceRef, l.Title); err != nil {
				return err
			}
		}
		fmt.Printf("tab       %s\n", l.URL)
	}
	return nil
}

func cmdLane(all []*Manifest, args []string) error {
	if len(args) == 1 && args[0] == "pull" {
		return pullLanes(all)
	}
	if len(args) != 2 {
		return fmt.Errorf("usage: proj lane <project> <%s>  |  proj lane pull", laneKeys())
	}
	m, err := findManifest(all, args[0])
	if err != nil {
		return err
	}
	lane, ok := laneByKey(args[1])
	if !ok {
		return fmt.Errorf("lane %q is not one of: %s", args[1], laneKeys())
	}
	if err := setManifestLane(m, lane.Key); err != nil {
		return err
	}
	b, err := loadBoard()
	if err != nil {
		return err
	}
	ws := b.workspaceFor(m)
	if ws == nil {
		fmt.Printf("%s → %s (manifest only; the project is not open)\n", m.Slug, lane.Label)
		return nil
	}
	groups, err := ensureLanes()
	if err != nil {
		return err
	}
	if _, err := cmux("workspace-group", "add", "--group", groups[lane.Key].Ref, "--workspace", ws.Ref); err != nil {
		return err
	}
	fmt.Printf("%s → %s\n", m.Slug, lane.Label)
	return nil
}

func pullLanes(all []*Manifest) error {
	b, err := loadBoard()
	if err != nil {
		return err
	}
	changed := 0
	for _, m := range all {
		ws := b.workspaceFor(m)
		if ws == nil {
			continue
		}
		live := b.liveLane(ws.Ref)
		if live == "" || live == m.Lane {
			continue
		}
		from := m.Lane
		if err := setManifestLane(m, live); err != nil {
			return err
		}
		fmt.Printf("%s: %s → %s\n", m.Slug, from, live)
		changed++
	}
	if changed == 0 {
		fmt.Println("manifests already match the board")
	}
	return nil
}

func cmdWt(cfg *config, all []*Manifest, args []string) error {
	if len(args) == 2 && args[0] == "rm" {
		m, err := findManifest(all, args[1])
		if err != nil {
			return err
		}
		if m.Location != locLocal {
			return errors.New("remote worktrees are not managed yet")
		}
		for _, r := range m.Repos {
			if !r.wantsWorktree() {
				continue
			}
			if err := removeWorktree(cfg.worktrees, m.Slug, r); err != nil {
				return fmt.Errorf("repo %s: %w", r.Path, err)
			}
			fmt.Println("removed", worktreeDir(cfg.worktrees, m.Slug, r))
		}
		// Only succeeds once the project directory is empty.
		_ = os.Remove(filepath.Join(cfg.worktrees, m.Slug))
		return nil
	}
	if len(args) > 0 && args[0] != "ls" {
		return errors.New("usage: proj wt [ls]  |  proj wt rm <project>")
	}

	type row struct{ repo, project, branch, state, dir string }
	var rows []row
	for _, m := range all {
		if m.Location != locLocal {
			continue
		}
		for _, r := range m.Repos {
			st := inspectRepo(cfg.worktrees, m.Slug, r)
			state := st.State
			if st.Detail != "" {
				state += ": " + st.Detail
			}
			if st.Dirty > 0 {
				state += fmt.Sprintf(" (%d changed)", st.Dirty)
			}
			branch := r.Branch
			if branch == "" {
				branch = "-"
			}
			rows = append(rows, row{filepath.Base(r.Path), m.Slug, branch, state, st.Dir})
		}
	}
	sort.SliceStable(rows, func(i, j int) bool { return rows[i].repo < rows[j].repo })
	tw := tabwriter.NewWriter(os.Stdout, 0, 0, 2, ' ', 0)
	fmt.Fprintln(tw, "REPO\tPROJECT\tBRANCH\tSTATE\tDIR")
	for _, r := range rows {
		fmt.Fprintf(tw, "%s\t%s\t%s\t%s\t%s\n", r.repo, r.project, r.branch, r.state, r.dir)
	}
	if err := tw.Flush(); err != nil {
		return err
	}
	for _, i := range validate(all) {
		if strings.HasPrefix(i.Msg, "repo ") {
			fmt.Println(i)
		}
	}
	return nil
}
