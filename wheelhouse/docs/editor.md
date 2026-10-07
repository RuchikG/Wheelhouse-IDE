# Code editor

Text files open in a [Monaco](https://microsoft.github.io/monaco-editor/) editor (the editor
from VS Code) instead of cmux's native text view. It lives inside the existing file panel, so
opening files from the file explorer or `cmux open <file>`, the dirty marker, save and revert,
reload when the file changes on disk, and session restore all work as before.

- Syntax highlighting for about 80 languages, loaded on demand.
- Monaco's editing features: multiple cursors, find and replace, folding, minimap, bracket matching.
- Save with ⌘S or the panel's save button.
- While the editor has keyboard focus, ⌘F (find in file), ⌘D (add the next occurrence to the
  selection) and ⌘/ (toggle line comment) go to the editor. Everywhere else they keep their cmux
  meaning, for example ⌘D splits the pane.
- A new-editor-tab button (curly braces) sits next to the new-terminal and new-browser buttons at
  the top right of every pane. It offers "New Untitled File", "Open File…" and "Open Folder…"; a
  file that is already open is focused instead of opened twice. A tab's right-click menu has the
  same choices under "New Editor Tab to Right". The button is the built-in action
  `wheelhouse.newEditor`, so it can be placed or removed like any other tab bar button in
  `cmux.json`.
- An untitled file asks where to save the first time you save it, and the tab then becomes that
  file. Its text is not kept if the app quits before that.
- Follows the panel's light or dark colors and the existing `fileEditor.*` settings (word wrap,
  line numbers, indent guides, current-line highlight, tab width).

## Folder tabs

"Open Folder…" opens a folder as one tab that works like a small editor window: the folder's file
tree on the left, a strip of the files you have opened from it, and the editor.

- Folders load when expanded. `.git` is hidden. The tree and the open file are refreshed when the
  window regains focus, and with the ↻ button.
- Right-click in the tree for New File…, New Folder…, Rename… and Move to Trash. Names are typed
  in place: Return accepts, Escape gives up. An open file follows its rename, unsaved edits
  included; a file moved to the Trash leaves the strip.
- "Find file" above the tree (⌘P) lists the files whose path contains every word you type, names
  first. ↑ and ↓ move, Return opens, Escape clears. `.git` and `node_modules` are left out, and a
  folder with more than 20,000 files is searched only in part.
- "Search in files" below it (⇧⌘F) lists the lines in the folder's files that contain the text you
  type, by file, as you type or on Return. ↑ and ↓ move, Return or a click opens the file with the
  match selected, and the list stays until Escape clears it. Letter case counts only when the text
  has a capital letter. Binary files, files over 1 MB, `.git` and `node_modules` are left out, and
  a search stops at 1,000 lines or after ten seconds.
- The files a folder had open, and which one was showing, come back when the folder is opened
  again, also after a restart. Unsaved edits do not.
- A folder tab keeps its open files and unsaved edits while another workspace is showing.
- ⌘S saves the open file and ⌥⌘S saves every file with unsaved edits; both are also in the
  right-click menu of the strip of open files. A dot marks a file with unsaved edits, and the tab
  itself shows one while any file has them. Closing such a file asks whether to save.
- While a folder tab has keyboard focus, ⌘P, ⇧⌘F and ⌥⌘S go to it. Everywhere else ⌘P and ⇧⌘F
  keep their cmux meaning.
- If something else (an agent, a terminal command) changed a file after it was opened here, saving
  asks before overwriting. A file with no unsaved edits just picks up the change.
- Go to definition and similar jumps open the target inside the same tab. Files outside the
  folder, such as a dependency's source, open read-only.
- The language server is rooted at the folder and shared by every file in the tab.

From a script, `wheelhouse/cli rpc file.open '{"paths":["/path/to/folder"]}'` opens a folder tab.

## Folders on a remote host

A folder tab can show a folder on another machine. Its files are read, edited and saved there,
and the language server runs there, so definitions and diagnostics follow that machine's code
and tools. The tree shows the host's name next to the folder's.

- In a workspace connected to a host with `cmux ssh`, "Open Folder…" asks for a path on that
  host (`~` works), starting from the terminal's directory.
- From a shell, `wheelhouse/remote-folder <host> <folder>` opens one in any workspace. The host is
  whatever `ssh <host>` reaches without asking for a password.
- The editor keeps one `ssh` connection open per folder tab and runs a small Python program
  over it that answers its file requests, so an operation costs one round trip instead of a new
  connection. The host needs `python3` (3.6 or later); nothing is installed on it. A second
  connection carries the language server, started through your login shell there so that tools
  on your own `PATH` (`~/go/bin`, for example) are found.
- There is no Trash on a remote host: the tree's menu says "Delete…" and deleting is final.
- If the connection drops, the next file operation opens a new one. Language features stay off
  until the tab is reopened.
- Single remote files opened from the Files sidebar are still read-only previews.

`cmux ssh` is cmux's own feature and installs its remote daemon on the host. On some hosts it
fails with "secure directory … has an ancestor not controlled by root or the effective user":
the home folder there sits under a folder owned by another account, which the daemon refuses
for its state. Give it a folder that passes the check with one line in `~/.pam_environment` on
the host, then connect again:

```
CMUX_REMOTE_STATE_DIR DEFAULT=/var/tmp/cmux-remote-<your user name>
```

## Language servers

Go files get completion, hover, go to definition, find references, rename, formatting and
diagnostics from [gopls](https://go.dev/gopls/), when `gopls` is installed (`go install
golang.org/x/tools/gopls@latest`). The app looks for it on your login shell's `PATH`. Each editor
runs `gopls -remote=auto`, a thin client of one shared gopls daemon, so open files of the same
module share one loaded workspace. The project root is the nearest `go.work`, else `go.mod`, above
the file. A jump to another file opens that file as a tab in the same pane.

Files that are not open are read when the editor needs them: the ⌘-hover preview of a definition
and the references list show them without opening a tab. In a folder tab, a rename that reaches
other files opens them in the strip with the change unsaved, so you can look and save each one.
A single-file tab holds only its own file, so there such a rename is refused as a whole with a
note to open the folder.

Other servers that speak LSP over standard input and output can be added, by file extension:

```sh
defaults write <bundle id> wheelhouse.languageServers -dict-add rs \
  '{ command = ("rust-analyzer"); rootMarkers = ("Cargo.toml"); }'
```

An entry with an empty `command` turns a built-in server off. Server start-up and failures are
logged under the `wheelhouse.code-editor` subsystem, category `language-server`.

## Known limits

- A folder tab cannot move a file to another folder, search with a pattern or replace across
  files, and it does not remember which folders were expanded.
- If a language server exits, its features stay off in that tab until the tab is reopened.
- A remote file opened on its own (from the Files sidebar, or by ⌘-clicking a path in a remote
  terminal) is a copy, as in cmux: it is not saved back. Open its folder instead.
- A remote folder tab does not notice a file changed on the host until the file is opened or
  the window regains focus, and it refuses to overwrite such a change without asking.
- Markdown source editing still uses the native editor.
- Other editor shortcuts that overlap an app shortcut still go to the app.

## Going back to the native editor

The editor can be turned off, which brings back cmux's native text view:

```sh
defaults write <bundle id> wheelhouse.codeEditor.enabled -bool false
```

The bundle id is `com.cmuxterm.app.debug.<tag>`, so `com.cmuxterm.app.debug.wheelhouse` by default.
