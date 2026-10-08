package main

import (
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
)

// archiveDir holds the files of projects taken off the board. Nothing reads it.
const archiveDir = "archive"

// archiveProject moves a project's file, and the record of its agent sessions when it has
// one, into <home>/archive and returns where the project file went. A name already taken
// there gets a number, so an earlier project of the same name is kept.
func archiveProject(home string, m *Manifest) (string, error) {
	dir := filepath.Join(home, archiveDir)
	if err := os.MkdirAll(dir, 0o755); err != nil {
		return "", err
	}
	stem := m.Slug
	for n := 2; ; n++ {
		taken := false
		for _, suffix := range []string{".yaml", ".sessions.json"} {
			if _, err := os.Lstat(filepath.Join(dir, stem+suffix)); err == nil {
				taken = true
			} else if !errors.Is(err, os.ErrNotExist) {
				return "", err
			}
		}
		if !taken {
			break
		}
		stem = m.Slug + "-" + strconv.Itoa(n)
	}
	sessions := filepath.Join(home, "sessions", m.Slug+".json")
	if err := os.Rename(sessions, filepath.Join(dir, stem+".sessions.json")); err != nil && !errors.Is(err, os.ErrNotExist) {
		return "", err
	}
	dst := filepath.Join(dir, stem+".yaml")
	return dst, os.Rename(m.File, dst)
}

func cmdRemove(cfg *config, all []*Manifest, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: proj rm <project>")
	}
	m, err := findManifest(all, args[0])
	if err != nil {
		return err
	}
	b, err := loadBoard()
	if err != nil {
		return err
	}
	if ws := b.workspaceFor(m); ws != nil {
		return fmt.Errorf("%s is open (%s); close its workspace first", m.Name, ws.Ref)
	}
	dst, err := archiveProject(cfg.home, m)
	if err != nil {
		return err
	}
	var rest []*Manifest
	for _, other := range all {
		if other != m {
			rest = append(rest, other)
		}
	}
	refreshBoard(cfg, rest)
	fmt.Printf("removed   %s  (kept as %s)\n", m.Name, tildePath(dst))
	if m.Location == locLocal {
		if dir := filepath.Join(cfg.worktrees, m.Slug); isDir(dir) {
			fmt.Printf("note  its worktrees stay in %s\n", tildePath(dir))
		}
	}
	return nil
}

func isDir(path string) bool {
	st, err := os.Stat(path)
	return err == nil && st.IsDir()
}
