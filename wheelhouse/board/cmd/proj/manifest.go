package main

import (
	"fmt"
	"os"
	"path/filepath"
	"regexp"
	"sort"
	"strings"

	"gopkg.in/yaml.v3"
)

const (
	locLocal  = "local"
	locRemote = "remote"
)

type Lane struct {
	Key   string
	Label string
}

// The board sidebar (sidebars/projects-board.js) matches lanes by Label.
var lanes = []Lane{
	{"design", "Design"},
	{"dev", "Dev"},
	{"review", "Review & Test"},
	{"release", "Release"},
	{"done", "Done"},
}

func laneByKey(key string) (Lane, bool) {
	for _, l := range lanes {
		if l.Key == key {
			return l, true
		}
	}
	return Lane{}, false
}

func laneKeys() string {
	keys := make([]string, len(lanes))
	for i, l := range lanes {
		keys[i] = l.Key
	}
	return strings.Join(keys, " | ")
}

type Repo struct {
	Path     string `yaml:"path"`
	Branch   string `yaml:"branch"`
	Base     string `yaml:"base"`
	Worktree *bool  `yaml:"worktree"`
}

// A repo with a branch gets its own worktree unless the manifest opts out.
func (r Repo) wantsWorktree() bool {
	if r.Worktree != nil {
		return *r.Worktree
	}
	return r.Branch != ""
}

type Link struct {
	Title string `yaml:"title"`
	URL   string `yaml:"url"`
}

type Agent struct {
	Name    string `yaml:"name"`
	Command string `yaml:"command"`
	Dir     string `yaml:"dir"`
}

type Manifest struct {
	Slug string `yaml:"-"`
	File string `yaml:"-"`

	Name     string  `yaml:"name"`
	Lane     string  `yaml:"lane"`
	Location string  `yaml:"location"`
	Host     string  `yaml:"host"`
	Summary  string  `yaml:"summary"`
	Dir      string  `yaml:"dir"`
	Repos    []Repo  `yaml:"repos"`
	Links    []Link  `yaml:"links"`
	Agents   []Agent `yaml:"agents"`
}

func loadManifest(path string) (*Manifest, error) {
	raw, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}
	m := &Manifest{}
	dec := yaml.NewDecoder(strings.NewReader(string(raw)))
	dec.KnownFields(true)
	if err := dec.Decode(m); err != nil {
		return nil, fmt.Errorf("%s: %w", filepath.Base(path), err)
	}
	m.File = path
	m.Slug = strings.TrimSuffix(filepath.Base(path), filepath.Ext(path))
	if m.Lane == "" {
		m.Lane = lanes[0].Key
	}
	if m.Location == "" {
		m.Location = locLocal
	}
	return m, nil
}

func loadAll(dir string) ([]*Manifest, error) {
	files, err := filepath.Glob(filepath.Join(dir, "*.yaml"))
	if err != nil {
		return nil, err
	}
	sort.Strings(files)
	var out []*Manifest
	for _, f := range files {
		if strings.HasPrefix(filepath.Base(f), "_") {
			continue
		}
		m, err := loadManifest(f)
		if err != nil {
			return nil, err
		}
		out = append(out, m)
	}
	return out, nil
}

func findManifest(all []*Manifest, slug string) (*Manifest, error) {
	for _, m := range all {
		if m.Slug == slug {
			return m, nil
		}
	}
	var slugs []string
	for _, m := range all {
		slugs = append(slugs, m.Slug)
	}
	return nil, fmt.Errorf("no project %q (have: %s)", slug, strings.Join(slugs, ", "))
}

type issue struct {
	Slug string
	Msg  string
	Warn bool
}

func (i issue) String() string {
	level := "error"
	if i.Warn {
		level = "warn"
	}
	return fmt.Sprintf("%-5s %s: %s", level, i.Slug, i.Msg)
}

func validate(all []*Manifest) []issue {
	var out []issue
	add := func(m *Manifest, warn bool, format string, a ...any) {
		out = append(out, issue{m.Slug, fmt.Sprintf(format, a...), warn})
	}

	names := map[string]string{}
	type checkout struct{ loc, path, branch string }
	branchOwner := map[checkout]string{}
	mainOwner := map[checkout]string{}

	for _, m := range all {
		if m.Name == "" {
			add(m, false, "name is required")
		}
		if other, ok := names[m.Name]; ok {
			add(m, false, "name %q is also used by %s", m.Name, other)
		}
		names[m.Name] = m.Slug
		for _, l := range lanes {
			if m.Name == l.Label {
				add(m, false, "name %q collides with a lane name", m.Name)
			}
		}
		if _, ok := laneByKey(m.Lane); !ok {
			add(m, false, "lane %q is not one of: %s", m.Lane, laneKeys())
		}
		if m.Location != locLocal && m.Location != locRemote {
			add(m, false, "location %q is not local or remote", m.Location)
		}
		for _, l := range m.Links {
			if l.URL == "" {
				add(m, false, "link %q has no url", l.Title)
			}
		}

		for _, r := range m.Repos {
			if r.Path == "" {
				add(m, false, "repo without a path")
				continue
			}
			if r.wantsWorktree() && r.Branch == "" {
				add(m, false, "repo %s: worktree needs a branch", r.Path)
				continue
			}
			if m.Location == locRemote {
				if r.wantsWorktree() {
					add(m, true, "repo %s: remote worktrees are not managed yet; the path is used as-is", r.Path)
				}
				continue
			}
			path := expandHome(r.Path)
			if r.Branch != "" {
				k := checkout{m.Location, path, r.Branch}
				if other, ok := branchOwner[k]; ok && other != m.Slug {
					add(m, false, "repo %s: branch %s is also claimed by %s (git allows one checkout per branch)", r.Path, r.Branch, other)
				}
				branchOwner[k] = m.Slug
			}
			if !r.wantsWorktree() {
				k := checkout{m.Location, path, ""}
				if other, ok := mainOwner[k]; ok && other != m.Slug {
					add(m, true, "repo %s: shares the main checkout with %s; give one of them a branch to get its own worktree", r.Path, other)
				}
				mainOwner[k] = m.Slug
			}
		}
	}
	return out
}

var laneLine = regexp.MustCompile(`(?m)^lane:.*$`)

// setManifestLane edits the file in place so comments and layout survive.
func setManifestLane(m *Manifest, lane string) error {
	raw, err := os.ReadFile(m.File)
	if err != nil {
		return err
	}
	text := string(raw)
	line := "lane: " + lane
	if laneLine.MatchString(text) {
		text = laneLine.ReplaceAllString(text, line)
	} else {
		text = strings.TrimRight(text, "\n") + "\n" + line + "\n"
	}
	if err := os.WriteFile(m.File, []byte(text), 0o644); err != nil {
		return err
	}
	m.Lane = lane
	return nil
}

func expandHome(p string) string {
	if p == "~" || strings.HasPrefix(p, "~/") {
		home, err := os.UserHomeDir()
		if err == nil {
			return filepath.Join(home, strings.TrimPrefix(p, "~"))
		}
	}
	return p
}
