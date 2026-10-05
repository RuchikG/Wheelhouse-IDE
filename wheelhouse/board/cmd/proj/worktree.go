package main

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
	"strings"
)

func git(dir string, args ...string) (string, error) {
	cmd := exec.Command("git", append([]string{"-C", dir}, args...)...)
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("git %s: %s", strings.Join(args, " "), msg)
	}
	return strings.TrimSpace(stdout.String()), nil
}

type wtEntry struct {
	Path   string
	Branch string
}

func listWorktrees(repo string) ([]wtEntry, error) {
	out, err := git(repo, "worktree", "list", "--porcelain")
	if err != nil {
		return nil, err
	}
	var entries []wtEntry
	for _, line := range strings.Split(out, "\n") {
		switch {
		case strings.HasPrefix(line, "worktree "):
			entries = append(entries, wtEntry{Path: strings.TrimPrefix(line, "worktree ")})
		case strings.HasPrefix(line, "branch ") && len(entries) > 0:
			entries[len(entries)-1].Branch = strings.TrimPrefix(strings.TrimPrefix(line, "branch "), "refs/heads/")
		}
	}
	return entries, nil
}

func samePath(a, b string) bool {
	if ra, err := filepath.EvalSymlinks(a); err == nil {
		a = ra
	}
	if rb, err := filepath.EvalSymlinks(b); err == nil {
		b = rb
	}
	return filepath.Clean(a) == filepath.Clean(b)
}

func hasRef(repo, ref string) bool {
	_, err := git(repo, "show-ref", "--verify", "--quiet", ref)
	return err == nil
}

func defaultBase(repo string) string {
	if head, err := git(repo, "symbolic-ref", "--short", "refs/remotes/origin/HEAD"); err == nil && head != "" {
		return head
	}
	for _, ref := range []string{"origin/master", "origin/main"} {
		if hasRef(repo, "refs/remotes/"+ref) {
			return ref
		}
	}
	return "HEAD"
}

func worktreeDir(root, slug string, r Repo) string {
	return filepath.Join(root, slug, filepath.Base(expandHome(r.Path)))
}

// checkoutDir is where the project works on this repo: its own worktree, or the main checkout.
func checkoutDir(root, slug string, r Repo) string {
	if r.wantsWorktree() {
		return worktreeDir(root, slug, r)
	}
	return expandHome(r.Path)
}

type wtState struct {
	Dir    string
	State  string // ok | missing | main | wrong-branch | blocked | error
	Detail string
	Dirty  int
}

func inspectRepo(root, slug string, r Repo) wtState {
	main := expandHome(r.Path)
	entries, err := listWorktrees(main)
	if err != nil {
		return wtState{Dir: main, State: "error", Detail: err.Error()}
	}
	st := wtState{Dir: checkoutDir(root, slug, r)}
	var current *wtEntry
	for i := range entries {
		if samePath(entries[i].Path, st.Dir) {
			current = &entries[i]
		}
	}
	switch {
	case current == nil:
		st.State = "missing"
		for _, e := range entries {
			if e.Branch == r.Branch {
				st.State = "blocked"
				st.Detail = "branch is checked out at " + e.Path
			}
		}
		return st
	case r.Branch != "" && current.Branch != r.Branch:
		st.State = "wrong-branch"
		st.Detail = "on " + orDetached(current.Branch)
	case r.wantsWorktree():
		st.State = "ok"
	default:
		st.State = "main"
	}
	if status, err := git(st.Dir, "status", "--porcelain"); err == nil && status != "" {
		st.Dirty = len(strings.Split(status, "\n"))
	}
	return st
}

func orDetached(branch string) string {
	if branch == "" {
		return "a detached HEAD"
	}
	return branch
}

// ensureCheckout returns the directory to work in, creating the project's worktree when needed.
// It never switches a branch or touches an existing checkout.
func ensureCheckout(root, slug string, r Repo) (dir, note string, err error) {
	main := expandHome(r.Path)
	entries, err := listWorktrees(main)
	if err != nil {
		return "", "", err
	}

	if !r.wantsWorktree() {
		for _, e := range entries {
			if samePath(e.Path, main) && r.Branch != "" && e.Branch != r.Branch {
				note = fmt.Sprintf("main checkout is on %s, manifest says %s", orDetached(e.Branch), r.Branch)
			}
		}
		return main, note, nil
	}

	target := worktreeDir(root, slug, r)
	for _, e := range entries {
		if samePath(e.Path, target) {
			if e.Branch != r.Branch {
				note = fmt.Sprintf("worktree is on %s, manifest says %s", orDetached(e.Branch), r.Branch)
			}
			return target, note, nil
		}
	}
	if _, statErr := os.Stat(target); statErr == nil {
		return "", "", fmt.Errorf("%s exists but is not a worktree of %s", target, main)
	}
	for _, e := range entries {
		if e.Branch != r.Branch {
			continue
		}
		hint := "remove that worktree or pick another branch"
		if samePath(e.Path, main) {
			hint = "switch the main checkout to another branch, or set `worktree: false` to work in it"
		}
		return "", "", fmt.Errorf("branch %s is already checked out at %s; %s", r.Branch, e.Path, hint)
	}

	if err := os.MkdirAll(filepath.Dir(target), 0o755); err != nil {
		return "", "", err
	}
	switch {
	case hasRef(main, "refs/heads/"+r.Branch):
		_, err = git(main, "worktree", "add", target, r.Branch)
		note = "created worktree on existing branch " + r.Branch
	case hasRef(main, "refs/remotes/origin/"+r.Branch):
		_, err = git(main, "worktree", "add", "--track", "-b", r.Branch, target, "origin/"+r.Branch)
		note = "created worktree tracking origin/" + r.Branch
	default:
		base := r.Base
		if base == "" {
			base = defaultBase(main)
		}
		_, err = git(main, "worktree", "add", "--no-track", "-b", r.Branch, target, base)
		at, _ := git(main, "log", "-1", "--format=%h, %cr", base)
		note = fmt.Sprintf("created worktree on new branch %s from %s (%s; not fetched)", r.Branch, base, at)
	}
	if err != nil {
		return "", "", err
	}
	return target, note, nil
}

// removeWorktree leaves the branch in place; git refuses when the worktree has changes.
func removeWorktree(root, slug string, r Repo) error {
	if !r.wantsWorktree() {
		return nil
	}
	target := worktreeDir(root, slug, r)
	if _, err := os.Stat(target); errors.Is(err, os.ErrNotExist) {
		return nil
	}
	_, err := git(expandHome(r.Path), "worktree", "remove", target)
	return err
}
