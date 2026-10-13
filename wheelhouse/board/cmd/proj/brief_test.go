package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
	"time"
)

func briefManifest(t *testing.T, cfg *config) *Manifest {
	t.Helper()
	path := filepath.Join(cfg.home, "projects", "refunds.yaml")
	writeFile(t, path, "name: Refunds\nlane: dev\nsummary: Split refunds\ndir: /work/refunds\n"+
		"links:\n  - title: PRD\n    url: https://example.com/prd\n")
	m, err := loadManifest(path)
	if err != nil {
		t.Fatal(err)
	}
	return m
}

func TestBriefNamesTheProjectItsMemoryAndTheRules(t *testing.T) {
	cfg := testConfig(t)
	m := briefManifest(t, cfg)
	text := renderBrief(cfg, m, nil, time.Time{}, time.Unix(1_800_000_000, 0))
	for _, want := range []string{
		"# Refunds: project brief",
		"- Lane: Dev (",
		"- Summary: Split refunds",
		"- Folder: /work/refunds",
		"- PRD: https://example.com/prd",
		memoryPath(cfg.home, "refunds"),
		"## If you are the project agent",
		"## If you are a new agent",
		"## Sessions so far\n\nNone.",
		"CLAUDE.md and AGENTS.md",
		"proj lane refunds <design | dev | review | release | done>",
		"Ask the user before anything that changes the project",
	} {
		if !strings.Contains(text, want) {
			t.Errorf("the brief lacks %q:\n%s", want, text)
		}
	}
}

func TestBriefListsOnlySessionsTheMemoryHasNotTakenIn(t *testing.T) {
	cfg := testConfig(t)
	m := briefManifest(t, cfg)
	now := time.Unix(1_800_000_000, 0)
	since := now.Add(-2 * time.Hour)
	at := func(hoursAgo float64) float64 { return float64(now.Unix()) - hoursAgo*3600 }
	sessions := []sessionRecord{
		{Name: "Codex", Title: "Before the memory", StartedAt: at(5), EndedAt: at(4)},
		{Name: "Claude Code", Title: "After  the\nmemory", StartedAt: at(1.5), EndedAt: at(1), Transcript: "/t/a.jsonl"},
		{Name: "Codex", Title: "Still going", StartedAt: at(3), Host: "build-box"},
		{Name: "Codex", Title: "The project agent itself", StartedAt: at(1), EndedAt: at(0.5), Role: "project"},
	}
	text := renderBrief(cfg, m, sessions, since, now)
	if strings.Contains(text, "Before the memory") || strings.Contains(text, "The project agent itself") {
		t.Errorf("a session the memory has is listed:\n%s", text)
	}
	after := strings.Index(text, "Claude Code, 30 min: After the memory\n  transcript: /t/a.jsonl")
	running := strings.Index(text, "Codex, running for 3 h, on build-box: Still going")
	if after < 0 || running < 0 || after > running {
		t.Errorf("want the later session first, then the running one:\n%s", text)
	}
	if !strings.Contains(text, "## Sessions since the memory was written (") {
		t.Errorf("the heading does not say since when:\n%s", text)
	}
}

func TestEnsureMemoryCreatesTheFileAndReportsWhenItWasWritten(t *testing.T) {
	cfg := testConfig(t)
	m := briefManifest(t, cfg)
	since, err := ensureMemory(cfg.home, m)
	if err != nil || !since.IsZero() {
		t.Fatalf("a new memory: since %v, err %v", since, err)
	}
	path := memoryPath(cfg.home, "refunds")
	if got := readFile(t, path); !strings.HasPrefix(got, "# Refunds: project memory") {
		t.Fatalf("unexpected template:\n%s", got)
	}
	if since, _ = ensureMemory(cfg.home, m); !since.IsZero() {
		t.Errorf("an untouched template counts as written: %v", since)
	}
	writeFile(t, path, "# Refunds\n\n- decided: one table\n")
	written := time.Unix(1_700_000_000, 0)
	if err := os.Chtimes(path, written, written); err != nil {
		t.Fatal(err)
	}
	if since, _ = ensureMemory(cfg.home, m); !since.Equal(written) {
		t.Errorf("since = %v, want %v", since, written)
	}
	if got := readFile(t, path); !strings.Contains(got, "one table") {
		t.Errorf("the memory was overwritten:\n%s", got)
	}
}

func TestSetTopLevelKeyKeepsTheRestOfTheFile(t *testing.T) {
	path := filepath.Join(t.TempDir(), "config", "config.yaml")
	if err := setTopLevelKey(path, "harness", "codex"); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, path); got != "harness: codex\n" {
		t.Fatalf("a new file: %q", got)
	}
	writeFile(t, path, "# mine\nname: Refunds\nharness: codex\nlinks:\n  - harness: no")
	if err := setTopLevelKey(path, "harness", "kit"); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, path); got != "# mine\nname: Refunds\nharness: kit\nlinks:\n  - harness: no" {
		t.Fatalf("after a change: %q", got)
	}
	if err := setTopLevelKey(path, "harness", ""); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, path); got != "# mine\nname: Refunds\nlinks:\n  - harness: no" {
		t.Fatalf("after a removal: %q", got)
	}
}

func TestHarnessIsSetForEveryProjectOrForOne(t *testing.T) {
	cfg := testConfig(t)
	m := briefManifest(t, cfg)
	all := []*Manifest{m}
	if err := cmdHarness(cfg, all, []string{"set", "codex"}); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, filepath.Join(cfg.home, "config.yaml")); got != "harness: codex\n" {
		t.Errorf("config.yaml: %q", got)
	}
	if err := cmdHarness(cfg, all, []string{"set", "refunds", "kit"}); err != nil {
		t.Fatal(err)
	}
	loaded, err := loadManifest(m.File)
	if err != nil || loaded.Harness != "kit" {
		t.Errorf("the project's harness: %q, err %v", loaded.Harness, err)
	}
	if err := cmdHarness(cfg, all, []string{"clear", "refunds"}); err != nil {
		t.Fatal(err)
	}
	if loaded, _ = loadManifest(m.File); loaded.Harness != "" {
		t.Errorf("after clear: %q", loaded.Harness)
	}
	if err := cmdHarness(cfg, all, []string{"set", "refunds", "rm -rf"}); err == nil {
		t.Error("a harness id with a space was accepted")
	}
}

func TestArchiveTakesTheMemoryAlongAndDropsTheBrief(t *testing.T) {
	cfg := testConfig(t)
	m := briefManifest(t, cfg)
	writeFile(t, memoryPath(cfg.home, "refunds"), "# Refunds\n")
	writeFile(t, briefPath(cfg.home, "refunds"), "# brief\n")
	if _, err := archiveProject(cfg.home, m); err != nil {
		t.Fatal(err)
	}
	if got := readFile(t, filepath.Join(cfg.home, archiveDir, "refunds.memory.md")); got != "# Refunds\n" {
		t.Errorf("the archived memory: %q", got)
	}
	if _, err := os.Stat(briefPath(cfg.home, "refunds")); !os.IsNotExist(err) {
		t.Errorf("the brief is still there: %v", err)
	}
}
