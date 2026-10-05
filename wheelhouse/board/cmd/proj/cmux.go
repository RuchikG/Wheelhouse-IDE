package main

import (
	"bytes"
	"encoding/json"
	"fmt"
	"os"
	"os/exec"
	"slices"
	"strings"
)

const cmuxAppBin = "/Applications/cmux.app/Contents/Resources/bin/cmux"

func cmuxBin() string {
	if b := os.Getenv("CMUX_BIN"); b != "" {
		return b
	}
	if b, err := exec.LookPath("cmux"); err == nil {
		return b
	}
	return cmuxAppBin
}

func cmux(args ...string) (string, error) {
	cmd := exec.Command(cmuxBin(), args...)
	cmd.Env = append(os.Environ(), "CMUX_QUIET=1")
	var stdout, stderr bytes.Buffer
	cmd.Stdout, cmd.Stderr = &stdout, &stderr
	if err := cmd.Run(); err != nil {
		msg := strings.TrimSpace(stderr.String())
		if msg == "" {
			msg = strings.TrimSpace(stdout.String())
		}
		if msg == "" {
			msg = err.Error()
		}
		return "", fmt.Errorf("cmux %s: %s", strings.Join(args, " "), msg)
	}
	return strings.TrimSpace(stdout.String()), nil
}

func cmuxJSON(v any, args ...string) error {
	out, err := cmux(append(args, "--json")...)
	if err != nil {
		return err
	}
	if err := json.Unmarshal([]byte(out), v); err != nil {
		return fmt.Errorf("cmux %s: unexpected output: %s", strings.Join(args, " "), out)
	}
	return nil
}

type workspace struct {
	Ref         string `json:"ref"`
	Title       string `json:"title"`
	CustomTitle string `json:"custom_title"`
	Description string `json:"description"`
	Dir         string `json:"current_directory"`
}

func listWorkspaces() ([]workspace, error) {
	var resp struct {
		Workspaces []workspace `json:"workspaces"`
	}
	if err := cmuxJSON(&resp, "workspace", "list"); err != nil {
		return nil, err
	}
	return resp.Workspaces, nil
}

type group struct {
	Ref        string   `json:"ref"`
	Name       string   `json:"name"`
	ExternalID string   `json:"external_id"`
	AnchorRef  string   `json:"anchor_workspace_ref"`
	MemberRefs []string `json:"member_workspace_refs"`
}

func listGroups() ([]group, error) {
	var resp struct {
		Groups []group `json:"groups"`
	}
	if err := cmuxJSON(&resp, "workspace-group", "list"); err != nil {
		return nil, err
	}
	return resp.Groups, nil
}

func laneExternalID(key string) string { return "ide-lane-" + key }

// ensureLanes creates the missing lane groups. Each group is owned by an anchor workspace
// that cmux generates, which is what lets a lane exist while it has no projects.
func ensureLanes() (map[string]group, error) {
	existing, err := listGroups()
	if err != nil {
		return nil, err
	}
	byKey := map[string]group{}
	for _, g := range existing {
		for _, l := range lanes {
			if g.ExternalID == laneExternalID(l.Key) {
				byKey[l.Key] = g
			}
		}
	}
	created := false
	home, _ := os.UserHomeDir()
	for _, l := range lanes {
		if _, ok := byKey[l.Key]; ok {
			continue
		}
		var resp struct {
			Group group `json:"group"`
		}
		if err := cmuxJSON(&resp, "workspace-group", "create", "--name", l.Label, "--cwd", home, "--external-id", laneExternalID(l.Key)); err != nil {
			return nil, err
		}
		byKey[l.Key] = resp.Group
		created = true
	}
	if created {
		for i, l := range lanes {
			if _, err := cmux("workspace-group", "move", byKey[l.Key].Ref, "--to-index", fmt.Sprint(i)); err != nil {
				return nil, err
			}
		}
	}
	return byKey, nil
}

type board struct {
	workspaces []workspace
	groups     []group
}

func loadBoard() (*board, error) {
	ws, err := listWorkspaces()
	if err != nil {
		return nil, err
	}
	gs, err := listGroups()
	if err != nil {
		return nil, err
	}
	return &board{ws, gs}, nil
}

func (b *board) isAnchor(ref string) bool {
	for _, g := range b.groups {
		if g.AnchorRef == ref && strings.HasPrefix(g.ExternalID, "ide-lane-") {
			return true
		}
	}
	return false
}

func (b *board) workspaceFor(m *Manifest) *workspace {
	for i, w := range b.workspaces {
		if w.Title != m.Name && w.CustomTitle != m.Name {
			continue
		}
		if b.isAnchor(w.Ref) {
			continue
		}
		return &b.workspaces[i]
	}
	return nil
}

// liveLane is the lane the workspace sits in on the board, which can differ from the manifest
// after a move made in the sidebar.
func (b *board) liveLane(ref string) string {
	for _, g := range b.groups {
		for _, l := range lanes {
			if g.ExternalID != laneExternalID(l.Key) {
				continue
			}
			if slices.Contains(g.MemberRefs, ref) {
				return l.Key
			}
		}
	}
	return ""
}

func firstPane(wsRef string) (string, error) {
	var resp struct {
		Panes []struct {
			Ref string `json:"ref"`
		} `json:"panes"`
	}
	if err := cmuxJSON(&resp, "list-panes", "--workspace", wsRef); err != nil {
		return "", err
	}
	if len(resp.Panes) == 0 {
		return "", fmt.Errorf("workspace %s has no panes", wsRef)
	}
	return resp.Panes[0].Ref, nil
}

type created struct {
	PaneRef    string `json:"pane_ref"`
	SurfaceRef string `json:"surface_ref"`
}
