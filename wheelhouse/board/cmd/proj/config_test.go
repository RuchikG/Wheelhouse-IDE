package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestEnsureHomeCreatesProjectsWithATemplateOnce(t *testing.T) {
	home := filepath.Join(t.TempDir(), "wheelhouse")
	t.Setenv("WHEELHOUSE_HOME", home)

	if created, err := ensureHome(); err != nil || !created {
		t.Fatalf("first run: created=%v err=%v", created, err)
	}
	template := filepath.Join(home, "projects", "_example.yaml")
	if _, err := os.Stat(template); err != nil {
		t.Fatalf("template missing: %v", err)
	}
	all, err := loadAll(filepath.Join(home, "projects"))
	if err != nil {
		t.Fatal(err)
	}
	if len(all) != 0 {
		t.Fatalf("the template counts as %d project(s)", len(all))
	}

	if err := os.Remove(template); err != nil {
		t.Fatal(err)
	}
	if created, err := ensureHome(); err != nil || created {
		t.Fatalf("second run: created=%v err=%v", created, err)
	}
	if _, err := os.Stat(template); err == nil {
		t.Fatal("an existing projects directory was given the template again")
	}
}
