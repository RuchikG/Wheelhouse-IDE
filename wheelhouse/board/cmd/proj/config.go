package main

import (
	"errors"
	"fmt"
	"io/fs"
	"os"
	"path/filepath"
	"strings"

	"gopkg.in/yaml.v3"
)

type config struct {
	home           string
	worktrees      string
	profile        string
	agentDir       string
	remoteHost     string
	remoteAgentDir string
	linkKinds      []LinkKind
}

type configFile struct {
	Worktrees      string     `yaml:"worktrees"`
	BrowserProfile string     `yaml:"browser_profile"`
	AgentDir       string     `yaml:"agent_dir"`
	RemoteHost     string     `yaml:"remote_host"`
	RemoteAgentDir string     `yaml:"remote_agent_dir"`
	LinkKinds      []LinkKind `yaml:"link_kinds"`
}

func configHome() (string, error) {
	if v := os.Getenv("WHEELHOUSE_HOME"); v != "" {
		return expandHome(v), nil
	}
	home, err := os.UserHomeDir()
	if err != nil {
		return "", err
	}
	return filepath.Join(home, ".config", "wheelhouse"), nil
}

func loadConfig() (*config, error) {
	home, err := configHome()
	if err != nil {
		return nil, err
	}
	if st, err := os.Stat(filepath.Join(home, "projects")); err != nil || !st.IsDir() {
		return nil, fmt.Errorf("no projects/ directory in %s; create it or set WHEELHOUSE_HOME", home)
	}

	var file configFile
	path := filepath.Join(home, "config.yaml")
	raw, err := os.ReadFile(path)
	switch {
	case errors.Is(err, fs.ErrNotExist):
	case err != nil:
		return nil, err
	default:
		dec := yaml.NewDecoder(strings.NewReader(string(raw)))
		dec.KnownFields(true)
		if err := dec.Decode(&file); err != nil {
			return nil, fmt.Errorf("%s: %w", path, err)
		}
	}

	cfg := &config{
		home:           home,
		worktrees:      expandHome(file.Worktrees),
		profile:        file.BrowserProfile,
		agentDir:       expandHome(file.AgentDir),
		remoteHost:     file.RemoteHost,
		remoteAgentDir: file.RemoteAgentDir,
		linkKinds:      file.LinkKinds,
	}
	if len(cfg.linkKinds) == 0 {
		cfg.linkKinds = defaultLinkKinds
	}
	if err := checkLinkKinds(cfg.linkKinds); err != nil {
		return nil, fmt.Errorf("%s: %w", path, err)
	}
	if v := os.Getenv("WHEELHOUSE_WORKTREES"); v != "" {
		cfg.worktrees = expandHome(v)
	}
	if v, ok := os.LookupEnv("WHEELHOUSE_BROWSER_PROFILE"); ok {
		cfg.profile = v
	}
	if v := os.Getenv("WHEELHOUSE_AGENT_DIR"); v != "" {
		cfg.agentDir = expandHome(v)
	}
	if v := os.Getenv("WHEELHOUSE_REMOTE_HOST"); v != "" {
		cfg.remoteHost = v
	}
	if v := os.Getenv("WHEELHOUSE_REMOTE_AGENT_DIR"); v != "" {
		cfg.remoteAgentDir = v
	}
	if cfg.worktrees == "" {
		cfg.worktrees = filepath.Join(home, "worktrees")
	}
	return cfg, nil
}

// sidebarSource finds projects-board.js next to the built binary (bin/proj → sidebars/).
func sidebarSource() (string, error) {
	exe, err := os.Executable()
	if err != nil {
		return "", err
	}
	if resolved, err := filepath.EvalSymlinks(exe); err == nil {
		exe = resolved
	}
	src := filepath.Join(filepath.Dir(filepath.Dir(exe)), "sidebars", "projects-board.js")
	if _, err := os.Stat(src); err != nil {
		return "", fmt.Errorf("board sidebar not found at %s; run proj from its build in wheelhouse/board", src)
	}
	return src, nil
}
