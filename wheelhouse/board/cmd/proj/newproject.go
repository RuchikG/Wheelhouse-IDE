package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"strings"
	"unicode"

	boardfiles "github.com/RuchikG/Wheelhouse-IDE/wheelhouse/board"
)

// newProjectMethod is the app's own form for a new project. Only Wheelhouse IDE has it.
const newProjectMethod = "wheelhouse.project.new"

const (
	exampleSlug = "example-project"
	exampleName = "Example Project"
)

// exampleLinks are offered on the example's card when the board has a link kind for them.
var exampleLinks = []Link{
	{Title: "Tech Design", URL: "https://github.com/RuchikG/Wheelhouse-IDE/blob/main/wheelhouse/docs/board.md"},
	{Title: "Tracker", URL: "https://github.com/RuchikG/Wheelhouse-IDE/issues"},
}

// slugFor turns a project name into its file name: "Checkout v2" → "checkout-v2".
func slugFor(name string) string {
	var b strings.Builder
	dash := false
	for _, r := range strings.ToLower(name) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			if dash && b.Len() > 0 {
				b.WriteByte('-')
			}
			dash = false
			b.WriteRune(r)
		} else {
			dash = true
		}
	}
	return b.String()
}

var homePath = regexp.MustCompile(`^~(/[A-Za-z0-9._@+-]+)+$`)

// tildePath writes a path under the home directory the way a person would.
func tildePath(path string) string {
	home, err := os.UserHomeDir()
	if err != nil || home == "" {
		return path
	}
	if path == home {
		return "~"
	}
	if rest, ok := strings.CutPrefix(path, home+string(filepath.Separator)); ok {
		return "~/" + rest
	}
	return path
}

func manifestText(m *Manifest) string {
	var b strings.Builder
	line := func(key, value string) {
		if value == "" {
			return
		}
		// A path under the home directory reads better unquoted, and YAML takes it as text.
		if homePath.MatchString(value) {
			fmt.Fprintf(&b, "%s: %s\n", key, value)
			return
		}
		fmt.Fprintf(&b, "%s: %s\n", key, yamlScalar(value))
	}
	line("name", m.Name)
	line("lane", m.Lane)
	line("summary", m.Summary)
	line("dir", m.Dir)
	if len(m.Links) > 0 {
		b.WriteString("links:\n")
		for _, l := range m.Links {
			fmt.Fprintf(&b, "  - title: %s\n    url: %s\n", yamlScalar(l.Title), yamlScalar(l.URL))
		}
	}
	if len(m.Agents) > 0 {
		b.WriteString("agents:\n")
		for _, a := range m.Agents {
			fmt.Fprintf(&b, "  - name: %s\n    command: %s\n", yamlScalar(a.Name), yamlScalar(a.Command))
		}
	}
	b.WriteString("# Links are added from the card's right-click menu. For repos with their own worktrees,\n")
	b.WriteString("# a remote host or more agents, see _example.yaml in this folder.\n")
	return b.String()
}

// addProject checks a new project against the others and writes its file.
func addProject(cfg *config, all []*Manifest, m *Manifest) ([]*Manifest, error) {
	m.Name = strings.TrimSpace(m.Name)
	if m.Name == "" {
		return nil, errors.New("the project needs a name")
	}
	m.Slug = slugFor(m.Name)
	if m.Slug == "" {
		return nil, fmt.Errorf("the name %q has no letters or digits to name its file with", m.Name)
	}
	m.File = filepath.Join(cfg.home, "projects", m.Slug+".yaml")
	if _, err := os.Lstat(m.File); err == nil {
		return nil, fmt.Errorf("a project file %s already exists", tildePath(m.File))
	}
	if m.Lane == "" {
		m.Lane = lanes[0].Key
	}
	m.Location = locLocal

	next := append(append([]*Manifest{}, all...), m)
	for _, i := range validate(next, cfg.linkKinds) {
		if i.Slug == m.Slug && !i.Warn {
			return nil, errors.New(i.Msg)
		}
	}
	if m.Dir != "" {
		if err := os.MkdirAll(expandHome(m.Dir), 0o755); err != nil {
			return nil, err
		}
	}
	if err := os.WriteFile(m.File, []byte(manifestText(m)), 0o644); err != nil {
		return nil, err
	}
	return next, nil
}

func cmdNew(cfg *config, all []*Manifest, args []string) error {
	const usage = "usage: proj new <name> [--dir <folder>] [--lane <lane>] [--summary <text>] [--agent <command>] [--no-open]"
	m := &Manifest{}
	open := true
	for i := 0; i < len(args); i++ {
		a := args[i]
		value := func() (string, error) {
			if i+1 >= len(args) {
				return "", fmt.Errorf("%s needs a value\n%s", a, usage)
			}
			i++
			return args[i], nil
		}
		var err error
		switch a {
		case "--name":
			m.Name, err = value()
		case "--dir":
			m.Dir, err = value()
		case "--lane":
			m.Lane, err = value()
		case "--summary":
			m.Summary, err = value()
		case "--agent":
			var command string
			if command, err = value(); strings.TrimSpace(command) != "" {
				m.Agents = []Agent{{Name: "agent", Command: strings.TrimSpace(command)}}
			}
		case "--no-open":
			open = false
		default:
			if strings.HasPrefix(a, "--") || m.Name != "" {
				return fmt.Errorf("unexpected argument %q\n%s", a, usage)
			}
			m.Name = a
		}
		if err != nil {
			return err
		}
	}
	if len(args) == 0 {
		if !appHas(newProjectMethod) {
			return errors.New(usage)
		}
		_, err := cmux("rpc", newProjectMethod, "{}")
		return err
	}
	if m.Dir != "" {
		dir, err := filepath.Abs(expandHome(m.Dir))
		if err != nil {
			return err
		}
		m.Dir = tildePath(dir)
	}
	m.Summary = strings.TrimSpace(m.Summary)

	next, err := addProject(cfg, all, m)
	if err != nil {
		return err
	}
	fmt.Printf("created   %s  (%s)\n", m.Name, tildePath(m.File))
	if !open {
		refreshBoard(cfg, next)
		return nil
	}
	return cmdOpen(cfg, next, []string{m.Slug, "--focus"})
}

// cmdExample puts a small project on the board, with a folder of its own, for a first look.
func cmdExample(cfg *config, all []*Manifest) error {
	for _, m := range all {
		if m.Slug == exampleSlug {
			return cmdOpen(cfg, all, []string{exampleSlug, "--focus"})
		}
	}
	dir := filepath.Join(cfg.home, exampleSlug)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return err
	}
	readme := filepath.Join(dir, "README.md")
	if _, err := os.Lstat(readme); errors.Is(err, os.ErrNotExist) {
		if err := os.WriteFile(readme, []byte(boardfiles.ExampleReadme), 0o644); err != nil {
			return err
		}
	}
	m := &Manifest{
		Name:    exampleName,
		Lane:    "dev",
		Summary: "A sample project: open it, try its links, then add your own",
		Dir:     tildePath(dir),
	}
	for _, l := range exampleLinks {
		if kind, ok := findKind(cfg.linkKinds, l.Title); ok {
			m.Links = append(m.Links, Link{Title: kind.Title, URL: l.URL})
		}
	}
	next, err := addProject(cfg, all, m)
	if err != nil {
		return err
	}
	fmt.Printf("created   %s  (%s)\n", m.Name, tildePath(dir))
	return cmdOpen(cfg, next, []string{m.Slug, "--focus"})
}
