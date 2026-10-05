# Notifications from agents on SSH hosts

Stock cmux releases report Claude Code's status (working, needs input, finished) only for agents
running on the Mac. An agent in a `cmux ssh` workspace is silent: nothing tells you it is waiting.

This hook closes the gap for notifications. Installed on the SSH host, it makes Claude Code call
`cmux notify` through the relay that `cmux ssh` sets up, so the workspace (and its card on the
[project board](../board/README.md)) shows an unread notification when the agent needs input or
finishes a turn.

```sh
./install.sh <ssh-destination>
```

That copies `cmux-notify-hook.sh` to `~/.claude/` on the host and registers it for the
`Notification` and `Stop` events in the host's `~/.claude/settings.json` (the previous file is kept
as `settings.json.bak-cmux-notify`). The host needs `jq`. Restart running agent sessions to pick
it up.

The hook does nothing when:

- the session is not in a `cmux ssh` terminal (headless `claude -p` jobs, plain ssh, cron);
- the session is on the Mac itself, where cmux already tracks agents;
- the relay on the host has its own Claude hooks (`cmux claude-hook`, in newer cmux builds), which
  report full status and make this hook unnecessary.

It reports notifications only, not the working/idle status shown for local agents.

To remove it, delete the two entries that point at `cmux-notify-hook.sh` from the host's
`~/.claude/settings.json`.
