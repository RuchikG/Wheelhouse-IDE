package main

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, path, text string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(text), 0o644); err != nil {
		t.Fatal(err)
	}
}

func readFile(t *testing.T, path string) string {
	t.Helper()
	raw, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(raw)
}

func TestArchiveProjectMovesTheFileAndItsSessions(t *testing.T) {
	cfg := testConfig(t)
	projects := filepath.Join(cfg.home, "projects")
	writeFile(t, filepath.Join(projects, "refunds.yaml"), "name: Refunds\n")
	writeFile(t, filepath.Join(projects, "search.yaml"), "name: Search\n")
	writeFile(t, filepath.Join(cfg.home, "sessions", "refunds.json"), `{"records":[]}`)

	all, err := loadAll(projects)
	if err != nil {
		t.Fatal(err)
	}
	m, err := findManifest(all, "refunds")
	if err != nil {
		t.Fatal(err)
	}
	dst, err := archiveProject(cfg.home, m)
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(cfg.home, "archive", "refunds.yaml"); dst != want {
		t.Fatalf("archived to %s, want %s", dst, want)
	}
	if got := readFile(t, dst); got != "name: Refunds\n" {
		t.Errorf("archived file holds %q", got)
	}
	if got := readFile(t, filepath.Join(cfg.home, "archive", "refunds.sessions.json")); got != `{"records":[]}` {
		t.Errorf("archived sessions hold %q", got)
	}
	if _, err := os.Stat(filepath.Join(cfg.home, "sessions", "refunds.json")); !os.IsNotExist(err) {
		t.Errorf("the sessions file is still in place: %v", err)
	}
	left, err := loadAll(projects)
	if err != nil {
		t.Fatal(err)
	}
	if len(left) != 1 || left[0].Slug != "search" {
		t.Fatalf("projects left: %v", left)
	}
}

func TestArchiveProjectKeepsAnEarlierProjectOfTheSameName(t *testing.T) {
	cfg := testConfig(t)
	projects := filepath.Join(cfg.home, "projects")
	archive := filepath.Join(cfg.home, "archive")
	writeFile(t, filepath.Join(archive, "refunds.yaml"), "name: Refunds\nsummary: first\n")
	writeFile(t, filepath.Join(archive, "refunds-2.sessions.json"), "second")
	writeFile(t, filepath.Join(projects, "refunds.yaml"), "name: Refunds\nsummary: third\n")

	all, err := loadAll(projects)
	if err != nil {
		t.Fatal(err)
	}
	dst, err := archiveProject(cfg.home, all[0])
	if err != nil {
		t.Fatal(err)
	}
	if want := filepath.Join(archive, "refunds-3.yaml"); dst != want {
		t.Fatalf("archived to %s, want %s", dst, want)
	}
	if got := readFile(t, filepath.Join(archive, "refunds.yaml")); got != "name: Refunds\nsummary: first\n" {
		t.Errorf("the earlier archived file now holds %q", got)
	}
	if got := readFile(t, filepath.Join(archive, "refunds-2.sessions.json")); got != "second" {
		t.Errorf("the earlier archived sessions now hold %q", got)
	}
	if _, err := os.Stat(filepath.Join(archive, "refunds-3.sessions.json")); !os.IsNotExist(err) {
		t.Errorf("a project without sessions got a sessions file: %v", err)
	}
}
