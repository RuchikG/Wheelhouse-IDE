package main

import (
	"encoding/json"
	"errors"
	"fmt"
)

// remoteFolderMethod is Wheelhouse IDE's socket method that opens a folder on another machine
// as an editor tab.
const remoteFolderMethod = "wheelhouse.remote_folder.open"

// projectFolders returns the folders a project works in and, for a remote project, the host
// that holds them: the project's own folder when it names one, else one per repository.
func projectFolders(cfg *config, m *Manifest) (folders []string, host string) {
	if m.Location == locRemote {
		host = m.Host
		if host == "" {
			host = cfg.remoteHost
		}
		if m.Dir != "" {
			return []string{m.Dir}, host
		}
		for _, r := range m.Repos {
			folders = append(folders, r.Path)
		}
		return folders, host
	}
	if m.Dir != "" {
		return []string{expandHome(m.Dir)}, ""
	}
	for _, r := range m.Repos {
		folders = append(folders, checkoutDir(cfg.worktrees, m.Slug, r))
	}
	return folders, ""
}

// cmdFolder opens the project's folders as editor tabs in its workspace.
func cmdFolder(cfg *config, all []*Manifest, args []string) error {
	if len(args) != 1 {
		return errors.New("usage: proj folder <project>")
	}
	m, err := findManifest(all, args[0])
	if err != nil {
		return err
	}
	b, err := loadBoard()
	if err != nil {
		return err
	}
	ws := b.workspaceFor(m)
	if ws == nil {
		return fmt.Errorf("%s is not open: run proj open %s first", m.Name, m.Slug)
	}
	folders, host := projectFolders(cfg, m)
	if len(folders) == 0 {
		return fmt.Errorf("%s has no folder: give its file a dir or a repository", m.Name)
	}
	if m.Location != locRemote {
		params, _ := json.Marshal(map[string]any{"paths": folders, "workspace_id": ws.Ref})
		_, err = cmux("rpc", "file.open", string(params))
		return err
	}
	if host == "" {
		return errors.New("remote project without a host: set host in the manifest or remote_host in config.yaml")
	}
	if !appHas(remoteFolderMethod) {
		return errors.New("opening a folder on a remote host needs Wheelhouse IDE")
	}
	for _, folder := range folders {
		params, _ := json.Marshal(map[string]any{"host": host, "path": folder, "workspace_id": ws.Ref})
		if _, err := cmux("rpc", remoteFolderMethod, string(params)); err != nil {
			return err
		}
	}
	return nil
}
