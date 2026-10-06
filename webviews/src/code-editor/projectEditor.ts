import * as monaco from "monaco-editor";
import { postToHost, type CodeEditorHostMessage, type CodeEditorOptions, type FileResult } from "./bridge";
import { applyEditorOptions, applyEditorTheme, createMonacoEditor, reveal, startOf } from "./editorChrome";
import { LanguageClients } from "./languageClient";

type OpenFile = {
  path: string;
  name: string;
  model: monaco.editor.ITextModel;
  /** The model version that matches what is on disk. */
  savedVersion: number;
  modified: number | undefined;
  readOnly: boolean;
  viewState: monaco.editor.ICodeEditorViewState | null;
  tab: HTMLElement;
};

type CloseChoice = "save" | "discard" | "cancel";

const TREE_WIDTH_KEY = "wheelhouse.project.treeWidth";
const TREE_INDENT = 14;

function element(tag: string, className: string, text?: string): HTMLElement {
  const node = document.createElement(tag);
  node.className = className;
  if (text !== undefined) {
    node.textContent = text;
  }
  return node;
}

function failureText(name: string, error: string | undefined): string {
  switch (error) {
    case "notText":
      return `${name} is not a text file.`;
    case "tooLarge":
      return `${name} is too large to open here.`;
    case "outsideProject":
      return `${name} is outside this folder and cannot be saved from here.`;
    default:
      return `${name} could not be read.`;
  }
}

/**
 * A folder as an editor: a lazily loaded file tree, a strip of the files
 * opened from it and one Monaco editor that shows the active file. The native
 * host lists, reads and writes files; this page keeps the open models and
 * their unsaved state.
 */
export class ProjectEditor {
  private readonly editor: monaco.editor.IStandaloneCodeEditor;
  private readonly languageClients = new LanguageClients();
  private readonly files = new Map<string, OpenFile>();
  private readonly expanded = new Set<string>();
  private readonly rows = new Map<string, HTMLElement>();
  private readonly pending = new Map<number, (result: unknown) => void>();
  private nextRequest = 1;
  private root = "";
  private active: OpenFile | undefined;
  private tabWidth: number | undefined;
  private reportedDirty = false;
  private noticeTimer: ReturnType<typeof setTimeout> | undefined;

  private readonly treeTitle = element("div", "project-tree-title");
  private readonly treeList = element("div", "project-tree-list");
  private readonly strip = element("div", "project-strip");
  private readonly notice = element("div", "project-notice");
  private readonly editorHost = element("div", "project-editor");
  private readonly empty = element("div", "project-empty", "Select a file to open it");

  constructor(container: HTMLElement) {
    container.classList.add("project");
    const tree = element("aside", "project-tree");
    const refresh = element("button", "project-tree-refresh", "↻");
    refresh.title = "Refresh";
    refresh.addEventListener("click", () => void this.renderTree());
    const header = element("div", "project-tree-header");
    header.append(this.treeTitle, refresh);
    tree.append(header, this.treeList);
    const resizer = element("div", "project-resizer");
    const main = element("main", "project-main");
    this.notice.hidden = true;
    this.editorHost.hidden = true;
    main.append(this.strip, this.notice, this.editorHost, this.empty);
    container.append(tree, resizer, main);
    this.installResizer(tree, resizer);

    this.editor = createMonacoEditor(this.editorHost);
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => void this.saveActive());
    monaco.editor.registerEditorOpener({
      openCodeEditor: (_source, resource, selectionOrPosition) => {
        if (resource.scheme !== "file") {
          return false;
        }
        void this.openFile(resource.fsPath, startOf(selectionOrPosition));
        return true;
      },
    });

    this.treeList.addEventListener("click", (event) => this.handleTreeClick(event));
    this.strip.addEventListener("click", (event) => this.handleStripClick(event));
    this.strip.addEventListener("auxclick", (event) => this.handleStripClick(event));
    window.addEventListener("focus", () => {
      void this.renderTree();
      if (this.active) {
        void this.reloadIfUnchanged(this.active);
      }
    });
  }

  receive(message: CodeEditorHostMessage): void {
    switch (message.type) {
      case "project":
        this.root = message.root;
        this.treeTitle.textContent = message.name;
        this.treeTitle.title = message.root;
        void this.renderTree();
        break;
      case "options":
        this.applyOptions(message.options);
        break;
      case "theme":
        applyEditorTheme(message.theme);
        document.documentElement.style.setProperty("--project-background", message.theme.background);
        document.documentElement.style.setProperty("--project-foreground", message.theme.foreground);
        break;
      case "focus":
        if (this.active) {
          this.editor.focus();
        }
        break;
      case "requestSave":
        void this.saveActive();
        break;
      case "reveal":
        if (this.active) {
          reveal(this.editor, message.line, message.column);
        }
        break;
      case "lspState":
        this.languageClients.receiveState(message.server, message.state);
        break;
      case "lsp":
        this.languageClients.receiveMessage(message.server, message.message);
        break;
      case "fsResult":
        this.resolve(message.id, message);
        break;
      case "confirmResult":
        this.resolve(message.id, message.choice);
        break;
      case "document":
        break;
    }
  }

  // Host requests

  private resolve(id: number, result: unknown): void {
    const resolve = this.pending.get(id);
    this.pending.delete(id);
    resolve?.(result);
  }

  private request<Result>(send: (id: number) => void): Promise<Result> {
    const id = this.nextRequest++;
    return new Promise((resolve) => {
      this.pending.set(id, resolve as (result: unknown) => void);
      send(id);
    });
  }

  private list(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "list", path }));
  }

  private read(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "read", path }));
  }

  private write(path: string, content: string, modified: number | undefined): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "write", path, content, modified }));
  }

  private confirmClose(name: string): Promise<CloseChoice> {
    return this.request((id) => postToHost({ type: "confirmClose", id, name }));
  }

  // File tree

  /** Lists the root and every expanded folder again, then swaps the tree in. */
  private async renderTree(): Promise<void> {
    if (!this.root) {
      return;
    }
    const rows = new Map<string, HTMLElement>();
    const list = document.createDocumentFragment();
    await this.renderDirectory(this.root, 0, list, rows);
    this.rows.clear();
    for (const [path, row] of rows) {
      this.rows.set(path, row);
    }
    this.treeList.replaceChildren(list);
    this.markActiveRow();
  }

  private async renderDirectory(
    directory: string,
    depth: number,
    into: DocumentFragment | HTMLElement,
    rows: Map<string, HTMLElement>,
  ): Promise<void> {
    const result = await this.list(directory);
    for (const entry of result.entries ?? []) {
      const path = `${directory}/${entry.name}`;
      const isExpanded = entry.isDirectory && this.expanded.has(path);
      const row = element("div", entry.isDirectory ? "project-row project-row-directory" : "project-row");
      row.dataset.path = path;
      row.dataset.depth = String(depth);
      row.style.paddingLeft = `${8 + depth * TREE_INDENT}px`;
      row.append(
        element("span", "project-row-chevron", entry.isDirectory ? (isExpanded ? "▾" : "▸") : ""),
        element("span", "project-row-name", entry.name),
      );
      into.append(row);
      rows.set(path, row);
      if (isExpanded) {
        const children = element("div", "project-row-children");
        into.append(children);
        await this.renderDirectory(path, depth + 1, children, rows);
      }
    }
  }

  private handleTreeClick(event: MouseEvent): void {
    const row = (event.target as HTMLElement).closest<HTMLElement>(".project-row");
    const path = row?.dataset.path;
    if (!row || !path) {
      return;
    }
    if (!row.classList.contains("project-row-directory")) {
      void this.openFile(path);
      return;
    }
    if (this.expanded.delete(path)) {
      if (row.nextElementSibling?.classList.contains("project-row-children")) {
        row.nextElementSibling.remove();
      }
      this.setChevron(row, false);
      for (const known of this.rows.keys()) {
        if (known.startsWith(`${path}/`)) {
          this.rows.delete(known);
        }
      }
      return;
    }
    this.expanded.add(path);
    this.setChevron(row, true);
    const children = element("div", "project-row-children");
    row.after(children);
    void this.renderDirectory(path, Number(row.dataset.depth ?? 0) + 1, children, this.rows).then(() =>
      this.markActiveRow(),
    );
  }

  private setChevron(row: HTMLElement, isExpanded: boolean): void {
    const chevron = row.querySelector(".project-row-chevron");
    if (chevron) {
      chevron.textContent = isExpanded ? "▾" : "▸";
    }
  }

  private markActiveRow(): void {
    for (const [path, row] of this.rows) {
      row.classList.toggle("project-row-active", path === this.active?.path);
    }
  }

  // Open files

  private async openFile(path: string, position?: { line: number; column: number }): Promise<void> {
    const name = path.slice(path.lastIndexOf("/") + 1);
    let file = this.files.get(path);
    if (!file) {
      const result = await this.read(path);
      if (!result.ok || result.content === undefined) {
        this.showNotice(failureText(name, result.error));
        return;
      }
      file = this.files.get(path) ?? this.addFile(path, name, result);
    }
    this.activate(file);
    if (position) {
      reveal(this.editor, position.line, position.column);
    }
  }

  private addFile(path: string, name: string, result: FileResult): OpenFile {
    const uri = monaco.Uri.file(path);
    const model = monaco.editor.getModel(uri) ?? monaco.editor.createModel(result.content ?? "", undefined, uri);
    if (this.tabWidth !== undefined) {
      model.updateOptions({ tabSize: this.tabWidth });
    }
    const tab = element("div", "project-tab");
    tab.dataset.path = path;
    tab.title = path.startsWith(`${this.root}/`) ? path.slice(this.root.length + 1) : path;
    tab.append(element("span", "project-tab-name", name), element("span", "project-tab-close", "×"));
    this.strip.append(tab);
    const file: OpenFile = {
      path,
      name,
      model,
      savedVersion: model.getAlternativeVersionId(),
      modified: result.modified,
      readOnly: result.readOnly ?? false,
      viewState: null,
      tab,
    };
    model.onDidChangeContent(() => this.updateDirty(file));
    this.files.set(path, file);
    this.languageClients.ensureFor(path);
    return file;
  }

  private activate(file: OpenFile): void {
    if (this.active && this.active !== file) {
      this.active.viewState = this.editor.saveViewState();
    }
    const isSwitch = this.active !== file;
    this.active = file;
    this.editorHost.hidden = false;
    this.empty.hidden = true;
    if (isSwitch) {
      this.editor.setModel(file.model);
      this.editor.updateOptions({ readOnly: file.readOnly });
      if (file.viewState) {
        this.editor.restoreViewState(file.viewState);
      }
    }
    for (const open of this.files.values()) {
      open.tab.classList.toggle("project-tab-active", open === file);
    }
    file.tab.scrollIntoView({ block: "nearest", inline: "nearest" });
    this.markActiveRow();
    this.editor.focus();
    if (isSwitch) {
      void this.reloadIfUnchanged(file);
    }
  }

  /** Picks up a change made outside the editor, unless the file has unsaved edits here. */
  private async reloadIfUnchanged(file: OpenFile): Promise<void> {
    if (this.isDirty(file)) {
      return;
    }
    const result = await this.read(file.path);
    if (!result.ok || result.content === undefined || this.isDirty(file) || !this.files.has(file.path)) {
      return;
    }
    file.modified = result.modified;
    if (result.content !== file.model.getValue()) {
      const viewState = this.active === file ? this.editor.saveViewState() : null;
      file.model.setValue(result.content);
      file.savedVersion = file.model.getAlternativeVersionId();
      if (viewState) {
        this.editor.restoreViewState(viewState);
      }
      this.updateDirty(file);
    }
  }

  private isDirty(file: OpenFile): boolean {
    return file.model.getAlternativeVersionId() !== file.savedVersion;
  }

  private updateDirty(file: OpenFile): void {
    file.tab.classList.toggle("project-tab-dirty", this.isDirty(file));
    const anyDirty = [...this.files.values()].some((open) => this.isDirty(open));
    if (anyDirty !== this.reportedDirty) {
      this.reportedDirty = anyDirty;
      postToHost({ type: "projectDirty", dirty: anyDirty });
    }
  }

  private async saveActive(): Promise<void> {
    if (this.active) {
      await this.save(this.active);
    }
  }

  private async save(file: OpenFile): Promise<void> {
    if (file.readOnly || !this.isDirty(file)) {
      return;
    }
    const version = file.model.getAlternativeVersionId();
    const result = await this.write(file.path, file.model.getValue(), file.modified);
    if (result.ok) {
      file.savedVersion = version;
      file.modified = result.modified;
      this.updateDirty(file);
    } else if (result.error !== "changedOnDisk") {
      this.showNotice(`${file.name} could not be saved.`);
    }
  }

  private handleStripClick(event: MouseEvent): void {
    const tab = (event.target as HTMLElement).closest<HTMLElement>(".project-tab");
    const file = tab?.dataset.path ? this.files.get(tab.dataset.path) : undefined;
    if (!file) {
      return;
    }
    const wantsClose = event.button === 1 || (event.target as HTMLElement).classList.contains("project-tab-close");
    if (wantsClose) {
      void this.closeFile(file);
    } else if (event.button === 0) {
      this.activate(file);
    }
  }

  private async closeFile(file: OpenFile): Promise<void> {
    if (this.isDirty(file)) {
      const choice = await this.confirmClose(file.name);
      if (choice === "cancel") {
        return;
      }
      if (choice === "save") {
        await this.save(file);
        if (this.isDirty(file)) {
          return;
        }
      }
    }
    if (!this.files.delete(file.path)) {
      return;
    }
    const neighbor = (file.tab.nextElementSibling ?? file.tab.previousElementSibling) as HTMLElement | null;
    file.tab.remove();
    if (this.active === file) {
      this.active = undefined;
      const next = neighbor?.dataset.path ? this.files.get(neighbor.dataset.path) : undefined;
      if (next) {
        this.activate(next);
      } else {
        this.editor.setModel(null);
        this.editorHost.hidden = true;
        this.empty.hidden = false;
        this.markActiveRow();
      }
    }
    file.model.dispose();
    this.updateDirty(file);
  }

  // Chrome

  private applyOptions(options: CodeEditorOptions): void {
    applyEditorOptions(this.editor, options);
    this.tabWidth = options.tabWidth;
    for (const file of this.files.values()) {
      file.model.updateOptions({ tabSize: options.tabWidth });
    }
  }

  private showNotice(text: string): void {
    this.notice.textContent = text;
    this.notice.hidden = false;
    if (this.noticeTimer !== undefined) {
      clearTimeout(this.noticeTimer);
    }
    this.noticeTimer = setTimeout(() => {
      this.notice.hidden = true;
    }, 5000);
  }

  private installResizer(tree: HTMLElement, resizer: HTMLElement): void {
    const apply = (width: number) => {
      tree.style.width = `${Math.min(Math.max(width, 140), window.innerWidth * 0.6)}px`;
    };
    try {
      const stored = Number(window.localStorage.getItem(TREE_WIDTH_KEY));
      if (stored > 0) {
        apply(stored);
      }
    } catch {
      // Storage can be unavailable for this page; the default width applies.
    }
    resizer.addEventListener("mousedown", (down) => {
      down.preventDefault();
      const startX = down.clientX;
      const startWidth = tree.getBoundingClientRect().width;
      const move = (event: MouseEvent) => apply(startWidth + event.clientX - startX);
      const up = () => {
        window.removeEventListener("mousemove", move);
        window.removeEventListener("mouseup", up);
        try {
          window.localStorage.setItem(TREE_WIDTH_KEY, String(tree.getBoundingClientRect().width));
        } catch {
          // See above.
        }
      };
      window.addEventListener("mousemove", move);
      window.addEventListener("mouseup", up);
    });
  }
}
