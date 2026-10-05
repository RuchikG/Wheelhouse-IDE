package main

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func newRepo(t *testing.T) string {
	t.Helper()
	repo := filepath.Join(t.TempDir(), "svc")
	if err := os.MkdirAll(repo, 0o755); err != nil {
		t.Fatal(err)
	}
	for _, args := range [][]string{
		{"init", "-q", "-b", "master"},
		{"-c", "user.name=t", "-c", "user.email=t@t", "commit", "-q", "--allow-empty", "-m", "init"},
	} {
		if _, err := git(repo, args...); err != nil {
			t.Fatal(err)
		}
	}
	return repo
}

func TestEnsureCheckoutIsolatesProjects(t *testing.T) {
	repo := newRepo(t)
	root := t.TempDir()

	dirA, note, err := ensureCheckout(root, "alpha", Repo{Path: repo, Branch: "feat/a"})
	if err != nil {
		t.Fatal(err)
	}
	if !strings.Contains(note, "new branch feat/a") {
		t.Errorf("note = %q", note)
	}
	dirB, _, err := ensureCheckout(root, "beta", Repo{Path: repo, Branch: "feat/b"})
	if err != nil {
		t.Fatal(err)
	}
	if dirA == dirB || dirA != filepath.Join(root, "alpha", "svc") {
		t.Errorf("dirs = %q, %q", dirA, dirB)
	}
	for dir, want := range map[string]string{dirA: "feat/a", dirB: "feat/b", repo: "master"} {
		if got, _ := git(dir, "symbolic-ref", "--short", "HEAD"); got != want {
			t.Errorf("%s is on %q, want %q", dir, got, want)
		}
	}

	again, note, err := ensureCheckout(root, "alpha", Repo{Path: repo, Branch: "feat/a"})
	if err != nil || again != dirA || note != "" {
		t.Errorf("second open = %q, %q, %v", again, note, err)
	}
	if upstream, err := git(dirA, "rev-parse", "--abbrev-ref", "feat/a@{upstream}"); err == nil {
		t.Errorf("new branch tracks %q, want no upstream", upstream)
	}
}

func TestEnsureCheckoutRefusesBusyBranch(t *testing.T) {
	repo := newRepo(t)
	root := t.TempDir()

	_, _, err := ensureCheckout(root, "alpha", Repo{Path: repo, Branch: "master"})
	if err == nil || !strings.Contains(err.Error(), "worktree: false") {
		t.Errorf("main-checkout branch: err = %v", err)
	}

	if _, _, err := ensureCheckout(root, "alpha", Repo{Path: repo, Branch: "feat/a"}); err != nil {
		t.Fatal(err)
	}
	_, _, err = ensureCheckout(root, "beta", Repo{Path: repo, Branch: "feat/a"})
	if err == nil || !strings.Contains(err.Error(), "already checked out") {
		t.Errorf("shared branch: err = %v", err)
	}
	if _, statErr := os.Stat(filepath.Join(root, "beta", "svc")); statErr == nil {
		t.Error("a worktree was created for the refused branch")
	}
}

func TestMainCheckoutIsLeftAlone(t *testing.T) {
	repo := newRepo(t)
	off := false
	dir, note, err := ensureCheckout(t.TempDir(), "alpha", Repo{Path: repo, Branch: "feat/x", Worktree: &off})
	if err != nil || dir != repo {
		t.Fatalf("dir = %q, err = %v", dir, err)
	}
	if !strings.Contains(note, "main checkout is on master") {
		t.Errorf("note = %q", note)
	}
	if got, _ := git(repo, "symbolic-ref", "--short", "HEAD"); got != "master" {
		t.Errorf("main checkout switched to %q", got)
	}
}

func TestRemoveWorktreeKeepsDirtyWork(t *testing.T) {
	repo := newRepo(t)
	root := t.TempDir()
	r := Repo{Path: repo, Branch: "feat/a"}
	dir, _, err := ensureCheckout(root, "alpha", r)
	if err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(filepath.Join(dir, "wip.txt"), []byte("x"), 0o644); err != nil {
		t.Fatal(err)
	}
	if st := inspectRepo(root, "alpha", r); st.State != "ok" || st.Dirty != 1 {
		t.Errorf("state = %+v", st)
	}
	if err := removeWorktree(root, "alpha", r); err == nil {
		t.Fatal("removed a worktree with uncommitted work")
	}
	if err := os.Remove(filepath.Join(dir, "wip.txt")); err != nil {
		t.Fatal(err)
	}
	if err := removeWorktree(root, "alpha", r); err != nil {
		t.Fatal(err)
	}
	if !hasRef(repo, "refs/heads/feat/a") {
		t.Error("branch was deleted with the worktree")
	}
	if st := inspectRepo(root, "alpha", r); st.State != "missing" {
		t.Errorf("state after remove = %+v", st)
	}
}

func TestValidateFlagsOverlap(t *testing.T) {
	off := false
	all := []*Manifest{
		{Slug: "a", Name: "A", Lane: "dev", Location: locLocal, Repos: []Repo{{Path: "/r/svc", Branch: "feat/x"}, {Path: "/r/lib"}}},
		{Slug: "b", Name: "B", Lane: "dev", Location: locLocal, Repos: []Repo{{Path: "/r/svc", Branch: "feat/x"}, {Path: "/r/lib"}}},
		{Slug: "c", Name: "C", Lane: "dev", Location: locLocal, Repos: []Repo{{Path: "/r/svc", Branch: "feat/y"}, {Path: "/r/lib", Branch: "feat/y", Worktree: &off}}},
		{Slug: "d", Name: "Dev", Lane: "nope", Location: locLocal},
	}
	var got []string
	for _, i := range validate(all) {
		got = append(got, i.String())
	}
	joined := strings.Join(got, "\n")
	for _, want := range []string{
		"error b: repo /r/svc: branch feat/x is also claimed by a",
		"warn  b: repo /r/lib: shares the main checkout with a",
		"warn  c: repo /r/lib: shares the main checkout with b",
		`error d: name "Dev" collides with a lane name`,
		`error d: lane "nope" is not one of`,
	} {
		if !strings.Contains(joined, want) {
			t.Errorf("missing %q in:\n%s", want, joined)
		}
	}
	if strings.Contains(joined, " a: ") || strings.Contains(joined, "feat/y is also") {
		t.Errorf("unexpected issue in:\n%s", joined)
	}
}
