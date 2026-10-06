package main

import (
	"strings"
	"testing"
)

func TestBoardDataKeepsOnlyUsableLinks(t *testing.T) {
	cfg := &config{profile: "work"}
	all := []*Manifest{
		{Name: "Checkout", Links: []Link{
			{Title: "Tech design", URL: "https://example.com/doc", Icon: "doc.text"},
			{URL: "https://example.com/untitled"},
			{Title: "No address"},
		}},
		{Name: "No links"},
	}

	data := boardDataFor(cfg, all)

	if data.BrowserProfile != "work" {
		t.Errorf("browser profile = %q, want work", data.BrowserProfile)
	}
	if _, ok := data.Projects["No links"]; ok {
		t.Error("a project without links should not be listed")
	}
	links := data.Projects["Checkout"].Links
	if len(links) != 2 {
		t.Fatalf("links = %+v, want 2", links)
	}
	if links[0] != (boardLink{Title: "Tech design", URL: "https://example.com/doc", Icon: "doc.text"}) {
		t.Errorf("first link = %+v", links[0])
	}
	if links[1].Icon != "link" {
		t.Errorf("a link without an icon or a telling title should get the link icon, got %q", links[1].Icon)
	}
	if links[1].Title != "https://example.com/untitled" {
		t.Errorf("a link without a title should be titled by its address, got %q", links[1].Title)
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
		Projects:       map[string]boardProject{"A </script> \"B\"": {Links: []boardLink{{Title: "Doc", URL: "https://example.com/?a=1&b=2"}}}},
		BrowserProfile: "work",
	}

	out, err := renderBoard(source, "/src/projects-board.js", data)
	if err != nil {
		t.Fatal(err)
	}

	lines := strings.Split(out, "\n")
	if !strings.HasPrefix(lines[0], boardGenerated+"/src/projects-board.js") {
		t.Errorf("first line = %q", lines[0])
	}
	want := `const BOARD = {"projects":{"A \u003c/script\u003e \"B\"":{"links":[{"title":"Doc","url":"https://example.com/?a=1\u0026b=2"}]}},"browserProfile":"work"};`
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
