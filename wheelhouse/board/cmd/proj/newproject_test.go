package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestSlugFor(t *testing.T) {
	cases := map[string]string{
		"Checkout v2":        "checkout-v2",
		"  Line-Item  Fix! ": "line-item-fix",
		"API":                "api",
		"…":                  "",
	}
	for name, want := range cases {
		if got := slugFor(name); got != want {
			t.Errorf("slugFor(%q) = %q, want %q", name, got, want)
		}
	}
}

func testConfig(t *testing.T) *config {
	t.Helper()
	home := t.TempDir()
	if err := os.MkdirAll(filepath.Join(home, "projects"), 0o755); err != nil {
		t.Fatal(err)
	}
	return &config{home: home, linkKinds: testKinds}
}

func TestAddProjectWritesAFileThatLoadsBack(t *testing.T) {
	cfg := testConfig(t)
	dir := filepath.Join(cfg.home, "work", "new folder")
	m := &Manifest{
		Name:    "  Refunds: phase #2 ",
		Lane:    "review",
		Summary: `Says "hi": to all`,
		Dir:     dir,
		Agents:  []Agent{{Name: "agent", Command: "claude --model 'x y'"}},
	}
	all, err := addProject(cfg, nil, m)
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 1 || m.Slug != "refunds-phase-2" {
		t.Fatalf("slug %q, %d project(s)", m.Slug, len(all))
	}
	if st, err := os.Stat(dir); err != nil || !st.IsDir() {
		t.Fatalf("the project folder was not created: %v", err)
	}
	loaded, err := loadAll(filepath.Join(cfg.home, "projects"))
	if err != nil {
		t.Fatal(err)
	}
	if len(loaded) != 1 {
		t.Fatalf("%d project(s) on disk", len(loaded))
	}
	got := loaded[0]
	if got.Name != "Refunds: phase #2" || got.Lane != "review" || got.Summary != m.Summary || got.Dir != dir ||
		got.Location != locLocal || len(got.Agents) != 1 || got.Agents[0].Command != "claude --model 'x y'" {
		t.Fatalf("loaded back as %+v", got)
	}
}

func TestAddProjectRefusesWhatTheBoardCannotShow(t *testing.T) {
	cfg := testConfig(t)
	all, err := addProject(cfg, nil, &Manifest{Name: "Refunds"})
	if err != nil {
		t.Fatal(err)
	}
	if all[0].Lane != lanes[0].Key {
		t.Fatalf("default lane %q", all[0].Lane)
	}
	cases := map[string]*Manifest{
		"needs a name":         {Name: "   "},
		"no letters":           {Name: "!!!"},
		"already exists":       {Name: "refunds"},
		"collides with a lane": {Name: "Dev"},
		"is not one of":        {Name: "Other", Lane: "shipping"},
	}
	for want, m := range cases {
		_, err := addProject(cfg, all, m)
		if err == nil || !strings.Contains(err.Error(), want) {
			t.Errorf("%q: got %v", want, err)
		}
	}
	files, _ := filepath.Glob(filepath.Join(cfg.home, "projects", "*.yaml"))
	if len(files) != 1 {
		t.Fatalf("a refused project left a file: %v", files)
	}
}

func TestAHomePathIsWrittenPlainAndLoadsBack(t *testing.T) {
	text := manifestText(&Manifest{Name: "Refunds", Lane: "dev", Dir: "~/work/refunds"})
	if !strings.Contains(text, "\ndir: ~/work/refunds\n") {
		t.Fatalf("dir line in:\n%s", text)
	}
	hidden := manifestText(&Manifest{Name: "Refunds", Dir: "~/.config/wheelhouse/example-project"})
	if !strings.Contains(hidden, "\ndir: ~/.config/wheelhouse/example-project\n") {
		t.Fatalf("dir line in:\n%s", hidden)
	}
	spaced := manifestText(&Manifest{Name: "Refunds", Dir: "~/my work: v2"})
	if !strings.Contains(spaced, `dir: "~/my work: v2"`) {
		t.Fatalf("dir line in:\n%s", spaced)
	}
	path := filepath.Join(t.TempDir(), "refunds.yaml")
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
	m, err := loadManifest(path)
	if err != nil || m.Dir != "~/work/refunds" {
		t.Fatalf("dir %q, err %v", m.Dir, err)
	}
}

func TestANewProjectFileTakesLinks(t *testing.T) {
	text := manifestText(&Manifest{Name: "Refunds", Lane: "dev"})
	edited, err := editLinks(text, testKinds[0], "https://example.com/prd")
	if err != nil {
		t.Fatal(err)
	}
	path := filepath.Join(t.TempDir(), "refunds.yaml")
	if err := os.WriteFile(path, []byte(edited), 0o644); err != nil {
		t.Fatal(err)
	}
	m, err := loadManifest(path)
	if err != nil {
		t.Fatal(err)
	}
	if len(m.Links) != 1 || m.Links[0].URL != "https://example.com/prd" {
		t.Fatalf("links %+v", m.Links)
	}
}
