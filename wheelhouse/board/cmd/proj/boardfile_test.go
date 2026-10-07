package main

import (
	"slices"
	"strings"
	"testing"
)

func TestBoardDataListsLinksByKind(t *testing.T) {
	cfg := &config{home: "/home/me/wheelhouse", profile: "work", linkKinds: []LinkKind{
		{Title: "PRD", Icon: "doc.text"},
		{Title: "Tech Design"},
		{Title: "Tracker", Icon: "ticket"},
	}}
	all := []*Manifest{
		{Name: "Checkout", Slug: "checkout", Links: []Link{
			{Title: "tech design", URL: "https://example.com/design"},
			{Title: "Dashboard", URL: "https://example.com/dashboard"},
			{Title: "Tracker"},
			{Title: "PRD", URL: "https://example.com/prd", Icon: "star"},
		}},
		{Name: "No links", Slug: "no-links"},
	}

	data := boardDataFor(cfg, all)

	if data.BrowserProfile != "work" {
		t.Errorf("browser profile = %q, want work", data.BrowserProfile)
	}
	if !strings.HasPrefix(data.Proj, "WHEELHOUSE_HOME='/home/me/wheelhouse' '") {
		t.Errorf("proj command = %q", data.Proj)
	}
	if data.Home != "/home/me/wheelhouse" {
		t.Errorf("home = %q", data.Home)
	}
	wantKinds := []boardKind{{"PRD", "doc.text"}, {"Tech Design", "doc.text"}, {"Tracker", "ticket"}}
	if !slices.Equal(data.Kinds, wantKinds) {
		t.Errorf("kinds = %+v, want %+v", data.Kinds, wantKinds)
	}
	if got, ok := data.Projects["No links"]; !ok || got.Slug != "no-links" || got.Links == nil || len(got.Links) != 0 {
		t.Errorf("a project without links should be listed with an empty list, got %+v (%v)", got, ok)
	}
	want := []boardLink{
		{Title: "PRD", URL: "https://example.com/prd", Icon: "star"},
		{Title: "Tech Design", URL: "https://example.com/design", Icon: "doc.text"},
	}
	if got := data.Projects["Checkout"]; got.Slug != "checkout" || !slices.Equal(got.Links, want) {
		t.Errorf("Checkout = %+v, want links %+v", got, want)
	}
}

func TestDefaultLinkIcon(t *testing.T) {
	for title, want := range map[string]string{
		"Tech design":      "doc.text",
		"PRD":              "doc.text",
		"Ticket":           "ticket",
		"Bug tracker":      "ticket",
		"CI pipeline":      "arrow.triangle.branch",
		"Release":          "arrow.triangle.branch",
		"Dashboard":        "link",
		"Redesign preview": "link",
	} {
		if got := defaultLinkIcon(title); got != want {
			t.Errorf("defaultLinkIcon(%q) = %q, want %q", title, got, want)
		}
	}
}

func TestRenderBoardReplacesTheDataLine(t *testing.T) {
	source := "// board\nconst BOARD = { projects: {}, browserProfile: \"\" };\nsidebar();\n"
	data := boardData{
		Projects:       map[string]boardProject{"A </script> \"B\"": {Slug: "a", Links: []boardLink{{Title: "Doc", URL: "https://example.com/?a=1&b=2"}}}},
		Kinds:          []boardKind{{Title: "Doc", Icon: "doc.text"}},
		BrowserProfile: "work",
		Proj:           "'/bin/proj'",
		Home:           "/h",
	}

	out, err := renderBoard(source, "/src/projects-board.js", data)
	if err != nil {
		t.Fatal(err)
	}

	lines := strings.Split(out, "\n")
	if !strings.HasPrefix(lines[0], boardGenerated+"/src/projects-board.js") {
		t.Errorf("first line = %q", lines[0])
	}
	want := `const BOARD = {"projects":{"A \u003c/script\u003e \"B\"":{"slug":"a","links":[{"title":"Doc","url":"https://example.com/?a=1\u0026b=2"}]}},"kinds":[{"title":"Doc","icon":"doc.text"}],"browserProfile":"work","proj":"'/bin/proj'","home":"/h"};`
	if lines[2] != want {
		t.Errorf("data line =\n%s\nwant\n%s", lines[2], want)
	}
	if lines[1] != "// board" || lines[3] != "sidebar();" {
		t.Errorf("the rest of the source changed: %q", lines)
	}
}

func TestRenderBoardNeedsTheDataLine(t *testing.T) {
	if _, err := renderBoard("sidebar();\n", "/src/projects-board.js", boardData{}); err == nil {
		t.Error("a source without the data line should be refused")
	}
}
