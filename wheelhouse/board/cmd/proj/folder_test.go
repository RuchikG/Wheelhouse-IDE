package main

import (
	"reflect"
	"testing"
)

func TestProjectFolders(t *testing.T) {
	cfg := &config{worktrees: "/wt", remoteHost: "buildbox"}
	cases := []struct {
		name    string
		m       *Manifest
		folders []string
		host    string
	}{
		{"its own folder", &Manifest{Slug: "a", Dir: "/code/a", Repos: []Repo{{Path: "/code/api"}}}, []string{"/code/a"}, ""},
		{"one per repository", &Manifest{Slug: "a", Repos: []Repo{{Path: "/code/api"}, {Path: "/code/web"}}},
			[]string{"/code/api", "/code/web"}, ""},
		{"a repository's worktree", &Manifest{Slug: "a", Repos: []Repo{{Path: "/code/api", Branch: "feat/x"}}},
			[]string{checkoutDir("/wt", "a", Repo{Path: "/code/api", Branch: "feat/x"})}, ""},
		{"nothing to open", &Manifest{Slug: "a"}, nil, ""},
		{"remote folder as written", &Manifest{Location: locRemote, Host: "devhost", Dir: "~/work/a"}, []string{"~/work/a"}, "devhost"},
		{"remote repositories on the configured host", &Manifest{Location: locRemote, Repos: []Repo{{Path: "~/src/api"}}},
			[]string{"~/src/api"}, "buildbox"},
	}
	for _, c := range cases {
		folders, host := projectFolders(cfg, c.m)
		if !reflect.DeepEqual(folders, c.folders) || host != c.host {
			t.Errorf("%s: got (%v, %q), want (%v, %q)", c.name, folders, host, c.folders, c.host)
		}
	}
}
