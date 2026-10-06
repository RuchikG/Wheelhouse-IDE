package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

var testKinds = []LinkKind{{Title: "PRD"}, {Title: "Tech Design"}, {Title: "Tracker"}}

func TestEditLinks(t *testing.T) {
	prd, design, tracker := testKinds[0], testKinds[1], testKinds[2]
	cases := []struct {
		name    string
		text    string
		kind    LinkKind
		address string
		want    string
	}{
		{
			name:    "adds the list to a file without one",
			text:    "name: A\nlane: dev\n",
			kind:    prd,
			address: "https://example.com/prd",
			want:    "name: A\nlane: dev\nlinks:\n  - title: PRD\n    url: https://example.com/prd\n",
		},
		{
			name:    "appends after the last entry and keeps what follows",
			text:    "name: A\nlinks:\n  - title: PRD\n    url: https://example.com/prd\n    icon: star   # ours\n\n# agents below\nagents: []\n",
			kind:    design,
			address: "https://example.com/design#part",
			want:    "name: A\nlinks:\n  - title: PRD\n    url: https://example.com/prd\n    icon: star   # ours\n  - title: Tech Design\n    url: https://example.com/design#part\n\n# agents below\nagents: []\n",
		},
		{
			name:    "replaces the address of a kind written in another case",
			text:    "links:\n- title: tech design\n  url: https://example.com/old  # v1\n- title: PRD\n  url: https://example.com/prd\n",
			kind:    design,
			address: "https://example.com/new",
			want:    "links:\n- title: tech design\n  url: https://example.com/new  # v1\n- title: PRD\n  url: https://example.com/prd\n",
		},
		{
			name:    "quotes an address that is not a plain value",
			text:    "links:\n  - title: PRD\n    url: https://example.com/prd\n",
			kind:    prd,
			address: "https://example.com/a?b=[1]",
			want:    "links:\n  - title: PRD\n    url: \"https://example.com/a?b=[1]\"\n",
		},
		{
			name:    "adds the address an entry lacks",
			text:    "links:\n  - title: Tracker\n",
			kind:    tracker,
			address: "https://example.com/t/1",
			want:    "links:\n  - title: Tracker\n    url: https://example.com/t/1\n",
		},
		{
			name:    "fills an empty key",
			text:    "name: A\nlinks:   # none yet\nlane: dev\n",
			kind:    prd,
			address: "https://example.com/prd",
			want:    "name: A\nlinks:   # none yet\n  - title: PRD\n    url: https://example.com/prd\nlane: dev\n",
		},
		{
			name:    "fills an empty inline list",
			text:    "name: A\nlinks: []\n",
			kind:    prd,
			address: "https://example.com/prd",
			want:    "name: A\nlinks:\n  - title: PRD\n    url: https://example.com/prd\n",
		},
		{
			name: "removes an entry with all its lines",
			text: "links:\n  - title: PRD\n    url: https://example.com/prd\n    icon: star\n  - title: Tracker\n    url: https://example.com/t/1\nlane: dev\n",
			kind: prd,
			want: "links:\n  - title: Tracker\n    url: https://example.com/t/1\nlane: dev\n",
		},
		{
			name: "removes the only entry",
			text: "links:\n  - title: PRD\n    url: https://example.com/prd\nlane: dev\n",
			kind: prd,
			want: "links:\nlane: dev\n",
		},
	}
	for _, c := range cases {
		got, err := editLinks(c.text, c.kind, c.address)
		if err != nil {
			t.Errorf("%s: %v", c.name, err)
			continue
		}
		if got != c.want {
			t.Errorf("%s:\n%s\nwant\n%s", c.name, got, c.want)
		}
	}
}

func TestEditLinksRefuses(t *testing.T) {
	for name, c := range map[string]struct {
		text    string
		address string
	}{
		"removing a link that is not there":    {"links:\n  - title: Tracker\n    url: https://example.com/t\n", ""},
		"removing from a file without links":   {"name: A\n", ""},
		"a list written on one line":           {"links: [{title: Tracker, url: https://example.com/t}]\n", "https://example.com/prd"},
		"an entry written on one line":         {"links:\n  - {title: Tracker, url: https://example.com/t}\n", "https://example.com/prd"},
		"links that are not a list":            {"links: later\n", "https://example.com/prd"},
		"an address folded over several lines": {"links:\n  - title: PRD\n    url: >\n      https://example.com/prd\n", "https://example.com/new"},
	} {
		if got, err := editLinks(c.text, testKinds[0], c.address); err == nil {
			t.Errorf("%s: want an error, got\n%s", name, got)
		}
	}
}

func TestSetManifestLinkWritesTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "a.yaml")
	if err := os.WriteFile(path, []byte("name: A\nlinks:\n  - title: PRD\n    url: https://example.com/prd\n"), 0o644); err != nil {
		t.Fatal(err)
	}
	m, err := loadManifest(path)
	if err != nil {
		t.Fatal(err)
	}

	if err := setManifestLink(m, testKinds[1], "https://example.com/design"); err != nil {
		t.Fatal(err)
	}
	if err := setManifestLink(m, testKinds[0], ""); err != nil {
		t.Fatal(err)
	}

	reloaded, err := loadManifest(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(reloaded.Links) != 1 || reloaded.Links[0] != (Link{Title: "Tech Design", URL: "https://example.com/design"}) {
		t.Errorf("links on disk = %+v", reloaded.Links)
	}
	if len(m.Links) != 1 || m.Links[0] != reloaded.Links[0] {
		t.Errorf("links in memory = %+v", m.Links)
	}
}

func TestCleanLinkURL(t *testing.T) {
	if got, err := cleanLinkURL("  https://example.com/a?b=1#c \n"); err != nil || got != "https://example.com/a?b=1#c" {
		t.Errorf("got %q, %v", got, err)
	}
	for _, bad := range []string{"", "example.com/a", "/a/b", "https://example.com/a b", "notes"} {
		if got, err := cleanLinkURL(bad); err == nil {
			t.Errorf("cleanLinkURL(%q) = %q, want an error", bad, got)
		}
	}
}

func TestValidateLinks(t *testing.T) {
	all := []*Manifest{{Slug: "a", Name: "A", Lane: "dev", Location: locLocal, Links: []Link{
		{Title: "PRD", URL: "https://example.com/prd"},
		{Title: "prd", URL: "https://example.com/prd2"},
		{Title: "Dashboard", URL: "https://example.com/d"},
	}}}

	var errs, warns []string
	for _, i := range validate(all, testKinds) {
		if i.Warn {
			warns = append(warns, i.Msg)
		} else {
			errs = append(errs, i.Msg)
		}
	}

	if len(errs) != 1 || !strings.Contains(errs[0], "more than one PRD link") {
		t.Errorf("errors = %q", errs)
	}
	if len(warns) != 1 || !strings.Contains(warns[0], `"Dashboard"`) {
		t.Errorf("warnings = %q", warns)
	}
}

func TestCheckLinkKinds(t *testing.T) {
	if err := checkLinkKinds(defaultLinkKinds); err != nil {
		t.Error(err)
	}
	if err := checkLinkKinds([]LinkKind{{Title: "Tech Design"}, {Title: "tech-design"}}); err == nil {
		t.Error("two spellings of one kind should be refused")
	}
	if err := checkLinkKinds([]LinkKind{{Title: "--"}}); err == nil {
		t.Error("a title without letters or digits should be refused")
	}
}
