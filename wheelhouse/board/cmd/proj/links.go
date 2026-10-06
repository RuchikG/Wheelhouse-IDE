package main

import (
	"errors"
	"fmt"
	"net/url"
	"os"
	"regexp"
	"strconv"
	"strings"
	"unicode"

	"gopkg.in/yaml.v3"
)

// A LinkKind is one of the chips a board card can carry. A project has at most one link of
// each kind.
type LinkKind struct {
	Title string `yaml:"title"`
	// Icon is an SF Symbol name; without one it is chosen from the title.
	Icon string `yaml:"icon"`
}

var defaultLinkKinds = []LinkKind{
	{Title: "PRD", Icon: "doc.text"},
	{Title: "Tech Solution", Icon: "lightbulb"},
	{Title: "Tech Design", Icon: "square.and.pencil"},
	{Title: "Tracker", Icon: "ticket"},
	{Title: "Pipeline", Icon: "arrow.triangle.branch"},
}

// kindKey makes "Tech Design", "tech design" and "tech-design" the same kind.
func kindKey(title string) string {
	var b strings.Builder
	for _, r := range strings.ToLower(title) {
		if unicode.IsLetter(r) || unicode.IsDigit(r) {
			b.WriteRune(r)
		}
	}
	return b.String()
}

func checkLinkKinds(kinds []LinkKind) error {
	seen := map[string]string{}
	for _, k := range kinds {
		key := kindKey(k.Title)
		if key == "" {
			return fmt.Errorf("link_kinds: %q is not a usable title", k.Title)
		}
		if other, ok := seen[key]; ok {
			return fmt.Errorf("link_kinds: %q and %q are the same kind", other, k.Title)
		}
		seen[key] = k.Title
	}
	return nil
}

func findKind(kinds []LinkKind, name string) (LinkKind, bool) {
	for _, k := range kinds {
		if kindKey(k.Title) == kindKey(name) {
			return k, true
		}
	}
	return LinkKind{}, false
}

func kindTitles(kinds []LinkKind) string {
	titles := make([]string, len(kinds))
	for i, k := range kinds {
		titles[i] = k.Title
	}
	return strings.Join(titles, ", ")
}

func (k LinkKind) icon() string {
	if k.Icon != "" {
		return k.Icon
	}
	return defaultLinkIcon(k.Title)
}

// linkOf returns the project's link of a kind.
func (m *Manifest) linkOf(kind LinkKind) (Link, bool) {
	for _, l := range m.Links {
		if kindKey(l.Title) == kindKey(kind.Title) {
			return l, true
		}
	}
	return Link{}, false
}

func cleanLinkURL(raw string) (string, error) {
	raw = strings.TrimSpace(raw)
	u, err := url.Parse(raw)
	if err != nil || u.Scheme == "" || u.Host == "" || strings.ContainsFunc(raw, unicode.IsSpace) {
		return "", fmt.Errorf("%q is not a full address like https://example.com/page", raw)
	}
	return raw, nil
}

const linkUsage = `usage: proj link [<project>]                show a project's links
       proj link [<project>] <kind> <url>   set a link
       proj link rm [<project>] <kind>      remove a link
Without <project>, the project of the workspace the command runs in is used.`

func cmdLink(cfg *config, all []*Manifest, args []string) error {
	remove := len(args) > 0 && args[0] == "rm"
	if remove {
		args = args[1:]
	}
	show := !remove && len(args) <= 1
	// What follows the optional project: nothing to show, a kind to remove, a kind and an
	// address to set.
	fixed := 2
	switch {
	case show:
		fixed = 0
	case remove:
		fixed = 1
	}
	var project string
	switch len(args) {
	case fixed:
		if project = currentProject(all); project == "" {
			return errors.New("not inside a project workspace; name the project\n" + linkUsage)
		}
	case fixed + 1:
		project, args = args[0], args[1:]
	default:
		return errors.New(linkUsage)
	}
	if show {
		m, err := findProject(all, project)
		if err != nil {
			return err
		}
		for _, k := range cfg.linkKinds {
			address := "-"
			if l, ok := m.linkOf(k); ok {
				address = l.URL
			}
			fmt.Printf("%-16s %s\n", k.Title, address)
		}
		return nil
	}

	m, err := findProject(all, project)
	if err != nil {
		return err
	}
	kind, ok := findKind(cfg.linkKinds, args[0])
	if !ok {
		return fmt.Errorf("%q is not a link kind (have: %s)", args[0], kindTitles(cfg.linkKinds))
	}
	address := ""
	if !remove {
		if address, err = cleanLinkURL(args[1]); err != nil {
			return err
		}
	}
	if err := setManifestLink(m, kind, address); err != nil {
		return err
	}
	if remove {
		fmt.Printf("unlinked  %s: %s\n", m.Name, kind.Title)
	} else {
		fmt.Printf("linked    %s: %s → %s\n", m.Name, kind.Title, address)
	}
	refreshBoard(cfg, all)
	return nil
}

// currentProject is the project of the workspace the command runs in: the one proj opened it
// for, else the one the workspace is named after.
func currentProject(all []*Manifest) string {
	if slug := os.Getenv("IDE_PROJECT"); slug != "" {
		return slug
	}
	id := os.Getenv("CMUX_WORKSPACE_ID")
	if id == "" {
		return ""
	}
	workspaces, err := listWorkspaces()
	if err != nil {
		return ""
	}
	for _, w := range workspaces {
		if w.ID != id {
			continue
		}
		for _, m := range all {
			if m.Name == w.Title || m.Name == w.CustomTitle {
				return m.Slug
			}
		}
	}
	return ""
}

// findProject accepts the project's file name or its board name.
func findProject(all []*Manifest, name string) (*Manifest, error) {
	for _, m := range all {
		if m.Name == name {
			return m, nil
		}
	}
	return findManifest(all, name)
}

// setManifestLink sets the project's link of a kind, or removes it when address is empty. It
// edits the file in place so comments and layout survive.
func setManifestLink(m *Manifest, kind LinkKind, address string) error {
	raw, err := os.ReadFile(m.File)
	if err != nil {
		return err
	}
	edited, err := editLinks(string(raw), kind, address)
	if err != nil {
		return fmt.Errorf("%s: %w", m.File, err)
	}
	// A line edit that went wrong must not reach the file.
	check := &Manifest{}
	dec := yaml.NewDecoder(strings.NewReader(edited))
	dec.KnownFields(true)
	if err := dec.Decode(check); err != nil {
		return fmt.Errorf("%s: the links could not be edited safely; edit them by hand", m.File)
	}
	if got, ok := check.linkOf(kind); ok != (address != "") || got.URL != address {
		return fmt.Errorf("%s: the links could not be edited safely; edit them by hand", m.File)
	}
	if err := os.WriteFile(m.File, []byte(edited), 0o644); err != nil {
		return err
	}
	m.Links = check.Links
	return nil
}

var errLinksInline = errors.New("the links are written on one line; rewrite them as a list with one entry per line")

func editLinks(text string, kind LinkKind, address string) (string, error) {
	var doc yaml.Node
	if err := yaml.Unmarshal([]byte(text), &doc); err != nil {
		return "", err
	}
	lines := strings.Split(text, "\n")
	entry := func(indent int) []string {
		pad := strings.Repeat(" ", indent)
		return []string{pad + "- title: " + yamlScalar(kind.Title), pad + "  url: " + yamlScalar(address)}
	}
	missing := fmt.Errorf("there is no %s link", kind.Title)

	var key, list *yaml.Node
	if len(doc.Content) == 1 && doc.Content[0].Kind == yaml.MappingNode {
		pairs := doc.Content[0].Content
		for i := 0; i+1 < len(pairs); i += 2 {
			if pairs[i].Value == "links" {
				key, list = pairs[i], pairs[i+1]
			}
		}
	} else if len(doc.Content) > 0 {
		return "", errors.New("not a project file")
	}

	switch {
	case key == nil:
		if address == "" {
			return "", missing
		}
		body := strings.TrimRight(text, "\n")
		if body != "" {
			body += "\n"
		}
		return body + "links:\n" + strings.Join(entry(2), "\n") + "\n", nil

	case list.Kind == yaml.ScalarNode && list.Tag == "!!null", list.Kind == yaml.SequenceNode && len(list.Content) == 0:
		if address == "" {
			return "", missing
		}
		indent := key.Column - 1
		if list.Kind == yaml.SequenceNode {
			lines[key.Line-1] = strings.Repeat(" ", indent) + "links:"
		}
		return strings.Join(insertLines(lines, key.Line, entry(indent+2)), "\n"), nil

	case list.Kind != yaml.SequenceNode:
		return "", errors.New("links is not a list")

	case list.Style&yaml.FlowStyle != 0:
		return "", errLinksInline
	}

	for _, item := range list.Content {
		if item.Kind != yaml.MappingNode || item.Style&yaml.FlowStyle != 0 || !startsWithDash(lines, item) {
			return "", errLinksInline
		}
	}
	for _, item := range list.Content {
		var title, target *yaml.Node
		for i := 0; i+1 < len(item.Content); i += 2 {
			switch item.Content[i].Value {
			case "title":
				title = item.Content[i+1]
			case "url":
				target = item.Content[i+1]
			}
		}
		if title == nil || kindKey(title.Value) != kindKey(kind.Title) {
			continue
		}
		switch {
		case address == "":
			return strings.Join(append(lines[:item.Line-1:item.Line-1], lines[lastLine(item):]...), "\n"), nil
		case target == nil:
			added := strings.Repeat(" ", item.Column-1) + "url: " + yamlScalar(address)
			return strings.Join(insertLines(lines, lastLine(item), []string{added}), "\n"), nil
		case target.Line != lastLine(target) || target.Style&(yaml.LiteralStyle|yaml.FoldedStyle) != 0:
			return "", errors.New("the address spans several lines; edit it by hand")
		}
		line := lines[target.Line-1][:target.Column-1] + yamlScalar(address)
		if target.LineComment != "" {
			line += "  " + target.LineComment
		}
		lines[target.Line-1] = line
		return strings.Join(lines, "\n"), nil
	}
	if address == "" {
		return "", missing
	}
	last := list.Content[len(list.Content)-1]
	return strings.Join(insertLines(lines, lastLine(last), entry(dashIndent(lines, last))), "\n"), nil
}

// dashIndent is the column of the "-" that starts a list entry.
func dashIndent(lines []string, item *yaml.Node) int {
	line := lines[item.Line-1]
	return len(line) - len(strings.TrimLeft(line, " "))
}

func startsWithDash(lines []string, item *yaml.Node) bool {
	return strings.HasPrefix(strings.TrimLeft(lines[item.Line-1], " "), "- ")
}

// lastLine is the last line a node occupies, taking every scalar as one line long.
func lastLine(n *yaml.Node) int {
	last := n.Line
	for _, c := range n.Content {
		last = max(last, lastLine(c))
	}
	return last
}

func insertLines(lines []string, after int, added []string) []string {
	out := make([]string, 0, len(lines)+len(added))
	out = append(out, lines[:after]...)
	out = append(out, added...)
	return append(out, lines[after:]...)
}

var plainScalar = regexp.MustCompile(`^[A-Za-z0-9/][A-Za-z0-9 /_.~:?&=%+@;!$*()#-]*$`)

// yamlScalar writes a value plain when that is safe and quoted otherwise.
func yamlScalar(s string) string {
	if plainScalar.MatchString(s) && !strings.HasSuffix(s, ":") && !strings.HasSuffix(s, " ") &&
		!strings.Contains(s, ": ") && !strings.Contains(s, " #") {
		return s
	}
	return strconv.Quote(s)
}
