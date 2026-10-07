package main

import "testing"

func TestRemoteStartup(t *testing.T) {
	shell := ` && exec "${SHELL:-/bin/sh}" -l`
	agent := func(command, dir string) *Manifest {
		return &Manifest{Agents: []Agent{{Name: "agent", Command: command, Dir: dir}}}
	}
	cases := []struct {
		name           string
		cfg            config
		m              *Manifest
		cwd            string
		command, typed string
	}{
		{"folder only", config{}, &Manifest{}, "~/code/api", "cd ~/code/api" + shell, ""},
		{"nothing to do", config{}, &Manifest{}, "", "", ""},
		{"agent in the workspace folder", config{}, agent("claude", ""), "~/code/api", "cd ~/code/api" + shell, "claude"},
		{"agent in the configured folder", config{remoteAgentDir: "~/work"}, agent("claude", ""), "~/code/api", "cd ~/work" + shell, "claude"},
		{"agent in its own folder", config{remoteAgentDir: "~/work"}, agent("claude", "~/code"), "~/code/api", "cd ~/code" + shell, "claude"},
		{"agent without a folder", config{}, agent("claude", ""), "", "", "claude"},
	}
	for _, c := range cases {
		command, typed := remoteStartup(&c.cfg, c.m, c.cwd)
		if command != c.command || typed != c.typed {
			t.Errorf("%s: got (%q, %q), want (%q, %q)", c.name, command, typed, c.command, c.typed)
		}
	}
}
