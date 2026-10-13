package main

import (
	"encoding/json"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"
	"time"
)

// A project's brief is what an agent started from the Agents panel is pointed at: the facts
// of the project file, the sessions the memory has not taken in yet, and the rules. It is
// written again before every start. The memory is the project agent's own file and is only
// created here.
const (
	briefDir  = "briefs"
	memoryDir = "memory"
	// At most this many sessions are listed in a brief, the latest first.
	briefSessions = 20
	// The role Wheelhouse IDE gives the sessions of a project's own agent.
	projectAgentRole = "project"
)

func briefPath(home, slug string) string  { return filepath.Join(home, briefDir, slug+".md") }
func memoryPath(home, slug string) string { return filepath.Join(home, memoryDir, slug+".md") }

// sessionRecord is one entry of <home>/sessions/<project>.json, which Wheelhouse IDE writes.
type sessionRecord struct {
	Name       string  `json:"name"`
	Title      string  `json:"title"`
	StartedAt  float64 `json:"startedAt"`
	EndedAt    float64 `json:"endedAt"`
	Host       string  `json:"host"`
	Directory  string  `json:"directory"`
	Transcript string  `json:"transcript"`
	Role       string  `json:"role"`
}

func loadSessions(home, slug string) []sessionRecord {
	raw, err := os.ReadFile(filepath.Join(home, "sessions", slug+".json"))
	if err != nil {
		return nil
	}
	var records []sessionRecord
	if json.Unmarshal(raw, &records) != nil {
		return nil
	}
	return records
}

func memoryTemplate(name string) string {
	return "# " + name + ": project memory\n\n" +
		"Kept by the project agent for every agent that works on this project. Keep it short:\n" +
		"what the next agent needs to start work without asking.\n\n" +
		"## Where it stands\n\n## Decisions\n\n## How we work here\n\n## Open\n"
}

// ensureMemory creates the project's memory file when it is missing and returns when the
// project agent last wrote it: the zero time while it still holds only the template.
func ensureMemory(home string, m *Manifest) (time.Time, error) {
	path := memoryPath(home, m.Slug)
	raw, err := os.ReadFile(path)
	if errors.Is(err, os.ErrNotExist) {
		if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
			return time.Time{}, err
		}
		return time.Time{}, os.WriteFile(path, []byte(memoryTemplate(m.Name)), 0o644)
	}
	if err != nil {
		return time.Time{}, err
	}
	if string(raw) == memoryTemplate(m.Name) {
		return time.Time{}, nil
	}
	st, err := os.Stat(path)
	if err != nil {
		return time.Time{}, err
	}
	return st.ModTime(), nil
}

func sessionLength(seconds float64) string {
	minutes := int(seconds / 60)
	switch {
	case minutes < 1:
		return "under a minute"
	case minutes < 60:
		return fmt.Sprintf("%d min", minutes)
	case minutes%60 == 0:
		return fmt.Sprintf("%d h", minutes/60)
	}
	return fmt.Sprintf("%d h %d min", minutes/60, minutes%60)
}

func oneLine(text string, limit int) string {
	text = strings.Join(strings.Fields(text), " ")
	if runes := []rune(text); len(runes) > limit {
		return string(runes[:limit-1]) + "…"
	}
	return text
}

func sessionLine(s sessionRecord, now time.Time) string {
	started := time.Unix(int64(s.StartedAt), 0)
	parts := []string{started.Format("2006-01-02 15:04"), s.Name}
	if s.EndedAt > 0 {
		parts = append(parts, sessionLength(s.EndedAt-s.StartedAt))
	} else {
		parts = append(parts, "running for "+sessionLength(float64(now.Unix())-s.StartedAt))
	}
	if s.Host != "" {
		parts = append(parts, "on "+s.Host)
	}
	line := "- " + strings.Join(parts, ", ")
	if s.Title != "" {
		line += ": " + oneLine(s.Title, 160)
	}
	if s.Transcript != "" {
		line += "\n  transcript: " + s.Transcript
	}
	return line
}

// renderBrief writes the brief of a project. `since` is when its memory was last written;
// sessions that ended before it are left out, as the memory has them.
func renderBrief(cfg *config, m *Manifest, sessions []sessionRecord, since, now time.Time) string {
	var b strings.Builder
	line := func(format string, a ...any) { fmt.Fprintf(&b, format+"\n", a...) }

	line("# %s: project brief", m.Name)
	line("")
	line("Written by Wheelhouse IDE on %s for the agents of this project. It is written again", now.Format("2006-01-02 15:04"))
	line("each time an agent is started from the Agents panel, so changes made here are lost.")
	line("")
	lane, _ := laneByKey(m.Lane)
	line("- Lane: %s (the lanes, in order: %s)", lane.Label, laneLabels())
	if m.Summary != "" {
		line("- Summary: %s", m.Summary)
	}
	folders, host := projectFolders(cfg, m)
	for _, folder := range folders {
		if host != "" {
			line("- Folder: %s on %s", folder, host)
		} else {
			line("- Folder: %s", folder)
		}
	}
	line("- Project file: %s", m.File)

	line("")
	line("## Links")
	line("")
	if len(m.Links) == 0 {
		line("None yet.")
	}
	for _, l := range m.Links {
		line("- %s: %s", l.Title, l.URL)
	}

	if len(m.Repos) > 0 {
		line("")
		line("## Repositories")
		line("")
		for _, r := range m.Repos {
			entry := "- " + r.Path
			if r.Branch != "" {
				entry += ", branch " + r.Branch
			}
			if m.Location == locLocal {
				if dir := checkoutDir(cfg.worktrees, m.Slug, r); dir != expandHome(r.Path) {
					entry += ", checked out in " + dir
				}
			}
			line("%s", entry)
		}
	}

	line("")
	line("## Project memory")
	line("")
	line("%s", memoryPath(cfg.home, m.Slug))
	line("")
	line("It holds what earlier sessions decided and learned. Read it before anything else.")

	line("")
	line("## If you are the project agent")
	line("")
	line("You keep this project's memory. Bring it up to date from the sessions listed below: read")
	line("a session's transcript where one is named, and keep only what the next agent needs to")
	line("start work: where the project stands, what was decided, how work is done here and what")
	line("is open. Take out what no longer holds. Then tell the user in a few lines where the")
	line("project stands.")

	line("")
	line("## If you are a new agent")
	line("")
	line("Read the memory for the background, and leave it and this brief as they are. Then say")
	line("in one line that you are ready, and wait for the user's task.")

	// The project agent wrote the memory in its own sessions, so those are left out.
	var listed []sessionRecord
	for _, s := range sessions {
		if s.Role != projectAgentRole && (s.EndedAt == 0 || s.EndedAt > float64(since.Unix())) {
			listed = append(listed, s)
		}
	}
	sort.SliceStable(listed, func(i, j int) bool { return listed[i].StartedAt > listed[j].StartedAt })
	if len(listed) > briefSessions {
		listed = listed[:briefSessions]
	}
	line("")
	if since.IsZero() {
		line("## Sessions so far")
	} else {
		line("## Sessions since the memory was written (%s)", since.Format("2006-01-02 15:04"))
	}
	line("")
	if len(listed) == 0 {
		line("None.")
	}
	for _, s := range listed {
		line("%s", sessionLine(s, now))
	}

	line("")
	line("## Instructions and skills")
	line("")
	line("Follow the instruction files in the project's folders, CLAUDE.md and AGENTS.md. Your")
	line("harness loaded its own: read the other one when it is there. Use the skills you have,")
	line("as in any other session.")

	line("")
	line("## What you can run")
	line("")
	line("- proj lane %s <%s>: move the project's card", m.Slug, laneKeys())
	line("- proj link %s <kind> <url>: set a link (kinds: %s)", m.Slug, kindTitles(cfg.linkKinds))
	line("- proj folder %s: open the project's folder as an editor tab", m.Slug)
	line("- proj ls: every project with its lane")
	if exe, err := os.Executable(); err == nil {
		line("")
		line("When proj is not on your PATH, it is %s.", exe)
	}

	line("")
	line("## Rules")
	line("")
	line("- Read and summarise without asking.")
	line("- Ask the user before anything that changes the project or leaves this machine: a lane")
	line("  move, a link, a commit, a push, a post.")
	return b.String()
}

// cmdBrief writes a project's brief, creates its memory file when there is none, and prints
// where both are and where its agents start.
func cmdBrief(cfg *config, all []*Manifest, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: proj brief <project>")
	}
	m, err := findManifest(all, args[0])
	if err != nil {
		return err
	}
	since, err := ensureMemory(cfg.home, m)
	if err != nil {
		return err
	}
	path := briefPath(cfg.home, m.Slug)
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	text := renderBrief(cfg, m, loadSessions(cfg.home, m.Slug), since, time.Now())
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		return err
	}
	dir := ""
	if folders, _ := projectFolders(cfg, m); len(folders) > 0 {
		dir = folders[0]
	}
	fmt.Printf("name\t%s\n", m.Name)
	fmt.Printf("brief\t%s\n", path)
	fmt.Printf("memory\t%s\n", memoryPath(cfg.home, m.Slug))
	fmt.Printf("dir\t%s\n", dir)
	return nil
}

var harnessID = regexp.MustCompile(`^[A-Za-z0-9._-]+$`)

// setTopLevelKey sets or, with an empty value, removes a top-level key of a YAML file in
// place, so its comments and layout survive. A missing file is created.
func setTopLevelKey(path, key, value string) error {
	raw, err := os.ReadFile(path)
	if err != nil && !errors.Is(err, os.ErrNotExist) {
		return err
	}
	text := string(raw)
	existing := regexp.MustCompile(`(?m)^` + regexp.QuoteMeta(key) + `:.*\n?`)
	switch {
	case value == "":
		text = existing.ReplaceAllString(text, "")
	case existing.MatchString(text):
		text = existing.ReplaceAllString(text, key+": "+value+"\n")
	default:
		if text != "" && !strings.HasSuffix(text, "\n") {
			text += "\n"
		}
		text += key + ": " + value + "\n"
	}
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return err
	}
	return os.WriteFile(path, []byte(text), 0o644)
}

// cmdHarness shows or sets the harness that agents started from the Agents panel run on:
// one for every project, and a project's own in its file.
func cmdHarness(cfg *config, all []*Manifest, args []string) error {
	const usage = "usage: proj harness  |  proj harness set [<project>] <harness>  |  proj harness clear [<project>]"
	if len(args) == 0 {
		fmt.Println("every project:", orNone(cfg.harness))
		for _, m := range all {
			if m.Harness != "" {
				fmt.Printf("%s: %s\n", m.Slug, m.Harness)
			}
		}
		return nil
	}
	verb, rest := args[0], args[1:]
	value := ""
	if verb == "set" {
		if len(rest) == 0 {
			return errors.New(usage)
		}
		value, rest = rest[len(rest)-1], rest[:len(rest)-1]
		if !harnessID.MatchString(value) {
			return fmt.Errorf("%q is not a harness id (letters, digits, . _ -)", value)
		}
	} else if verb != "clear" {
		return errors.New(usage)
	}
	switch len(rest) {
	case 0:
		return setTopLevelKey(filepath.Join(cfg.home, "config.yaml"), "harness", value)
	case 1:
		m, err := findManifest(all, rest[0])
		if err != nil {
			return err
		}
		return setTopLevelKey(m.File, "harness", value)
	}
	return errors.New(usage)
}

func orNone(text string) string {
	if text == "" {
		return "not set"
	}
	return text
}
