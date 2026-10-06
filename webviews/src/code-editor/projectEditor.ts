import * as monaco from "monaco-editor";
import { postToHost, type CodeEditorHostMessage, type CodeEditorOptions, type FileResult } from "./bridge";
import {
  applyEditorOptions,
  applyEditorTheme,
  createFileModels,
  createMonacoEditor,
  reveal,
  startOf,
} from "./editorChrome";
import { invalidName, isWithin, movedPath } from "./fileFinder";
import { HostRequests } from "./hostRequests";
import { LanguageClients } from "./languageClient";
import { FileFinder } from "./projectFinder";
import { showMenu, type MenuItem } from "./projectMenu";

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

function baseName(path: string): string {
  return path.slice(path.lastIndexOf("/") + 1);
}

function parentOf(path: string): string {
  return path.slice(0, path.lastIndexOf("/"));
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
  private readonly host = new HostRequests();
  private readonly fileModels = createFileModels((path) => this.host.read(path));
  // A rename that reaches into a file that is not open opens it, so its edits show as unsaved.
  private readonly languageClients = new LanguageClients(async (file) => {
    const loaded = file.scheme === "file" ? await this.loadFile(file.fsPath) : undefined;
    return loaded !== undefined && !loaded.readOnly;
  });
  private readonly files = new Map<string, OpenFile>();
  private readonly expanded = new Set<string>();
  private readonly rows = new Map<string, HTMLElement>();
  private root = "";
  /** The host that holds the folder; undefined for this machine, which has a Trash. */
  private remote: string | undefined;
  private active: OpenFile | undefined;
  private tabWidth: number | undefined;
  private reportedDirty = false;
  /** The open files as last told to the host, which remembers them for the next launch. */
  private reportedFiles = "";
  private isRestoring = false;
  /** A name is being typed into the tree, which must not be redrawn under it. */
  private isNaming = false;
  private noticeTimer: ReturnType<typeof setTimeout> | undefined;

  private readonly treeTitle = element("div", "project-tree-title");
  private readonly treeHost = element("div", "project-tree-host");
  private readonly treeList = element("div", "project-tree-list");
  private readonly strip = element("div", "project-strip");
  private readonly notice = element("div", "project-notice");
  private readonly editorHost = element("div", "project-editor");
  private readonly empty = element("div", "project-empty", "Select a file to open it");
  private readonly finder = new FileFinder(
    async () => {
      const result = await this.host.index(this.root);
      return { paths: result.paths ?? [], isComplete: result.complete ?? true };
    },
    (path) => void this.openFile(`${this.root}/${path}`),
    (isSearching) => {
      this.treeList.hidden = isSearching;
    },
  );

  constructor(private readonly container: HTMLElement) {
    container.classList.add("project");
    const tree = element("aside", "project-tree");
    const refresh = element("button", "project-tree-refresh", "↻");
    refresh.title = "Refresh";
    refresh.addEventListener("click", () => void this.renderTree());
    const header = element("div", "project-tree-header");
    this.treeHost.hidden = true;
    header.append(this.treeTitle, this.treeHost, refresh);
    tree.append(header, this.finder.input, this.finder.list, this.treeList);
    const resizer = element("div", "project-resizer");
    const main = element("main", "project-main");
    this.notice.hidden = true;
    this.editorHost.hidden = true;
    main.append(this.strip, this.notice, this.editorHost, this.empty);
    container.append(tree, resizer, main);
    this.installResizer(tree, resizer);

    this.editor = createMonacoEditor(this.editorHost, this.fileModels);
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => void this.saveActive());
    monaco.editor.registerEditorOpener({
      openCodeEditor: async (_source, resource, selectionOrPosition) => {
        if (resource.scheme !== "file") {
          return false;
        }
        await this.openFile(resource.fsPath, startOf(selectionOrPosition));
        return true;
      },
    });

    this.treeList.addEventListener("click", (event) => this.handleTreeClick(event));
    this.treeList.addEventListener("contextmenu", (event) => this.showTreeMenu(event));
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
    if (this.host.receive(message)) {
      return;
    }
    switch (message.type) {
      case "project":
        this.root = message.root;
        this.remote = message.remote;
        this.treeTitle.textContent = message.name;
        this.treeTitle.title = message.remote ? `${message.remote}:${message.root}` : message.root;
        this.treeHost.textContent = message.remote ?? "";
        this.treeHost.hidden = !message.remote;
        void this.renderTree();
        if (this.files.size === 0) {
          void this.restore(message.openFiles ?? [], message.activeFile);
        }
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
        // The keyboard stays with a field the user is typing in: the finder, a name in the tree.
        if (this.active && !(document.activeElement instanceof HTMLInputElement)) {
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
    }
  }

  // File tree

  /** Lists the root and every expanded folder again, then swaps the tree in. */
  private async renderTree(): Promise<void> {
    if (!this.root || this.isNaming) {
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
    const result = await this.host.list(directory);
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
    if (!row || !path || this.isNaming) {
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

  // Changing the tree

  private showTreeMenu(event: MouseEvent): void {
    event.preventDefault();
    if (!this.root || this.isNaming) {
      return;
    }
    const row = (event.target as HTMLElement).closest<HTMLElement>(".project-row");
    const path = row?.dataset.path;
    const folder = !row || !path ? this.root : row.classList.contains("project-row-directory") ? path : parentOf(path);
    const items: MenuItem[] = [
      { label: "New File…", run: () => void this.create("file", folder) },
      { label: "New Folder…", run: () => void this.create("folder", folder) },
    ];
    if (path) {
      items.push(
        { label: "Rename…", run: () => void this.rename(path) },
        { label: this.remote ? "Delete…" : "Move to Trash", run: () => void this.trash(path) },
      );
    }
    showMenu(this.container, event.clientX, event.clientY, items);
  }

  /**
   * Takes a name typed into `row`. Return accepts it, Escape or clicking away
   * gives it up, which resolves to undefined.
   */
  private askName(row: HTMLElement, current: string): Promise<string | undefined> {
    const input = document.createElement("input");
    input.className = "project-row-input";
    input.value = current;
    input.spellcheck = false;
    row.append(input);
    this.isNaming = true;
    input.focus();
    const dot = current.lastIndexOf(".");
    input.setSelectionRange(0, dot > 0 ? dot : current.length);
    return new Promise((resolve) => {
      const finish = (name: string | undefined) => {
        if (!this.isNaming) {
          return;
        }
        this.isNaming = false;
        input.remove();
        resolve(name);
      };
      input.addEventListener("keydown", (event) => {
        event.stopPropagation();
        if (event.key === "Escape") {
          finish(undefined);
        } else if (event.key === "Enter") {
          const name = input.value.trim();
          const problem = invalidName(name);
          if (problem) {
            this.showNotice(problem);
          } else {
            finish(name);
          }
        }
      });
      input.addEventListener("click", (event) => event.stopPropagation());
      input.addEventListener("blur", () => finish(undefined));
    });
  }

  private async create(kind: "file" | "folder", folder: string): Promise<void> {
    if (folder !== this.root && !this.expanded.has(folder)) {
      this.expanded.add(folder);
      await this.renderTree();
    }
    const folderRow = this.rows.get(folder);
    const children = folder === this.root ? this.treeList : folderRow?.nextElementSibling;
    if (!children) {
      return;
    }
    const depth = folderRow ? Number(folderRow.dataset.depth ?? 0) + 1 : 0;
    const row = element("div", "project-row");
    row.style.paddingLeft = `${8 + depth * TREE_INDENT}px`;
    row.append(element("span", "project-row-chevron", kind === "folder" ? "▸" : ""));
    children.prepend(row);
    const name = await this.askName(row, "");
    row.remove();
    if (name === undefined) {
      return;
    }
    const path = `${folder}/${name}`;
    const result = kind === "file" ? await this.host.createFile(path) : await this.host.createDirectory(path);
    if (!result.ok) {
      this.showNotice(result.error === "exists" ? `${name} already exists.` : `${name} could not be created.`);
      return;
    }
    await this.renderTree();
    if (kind === "file") {
      await this.openFile(path);
    }
  }

  private async rename(path: string): Promise<void> {
    const row = this.rows.get(path);
    const label = row?.querySelector<HTMLElement>(".project-row-name");
    if (!row || !label) {
      return;
    }
    const current = baseName(path);
    label.hidden = true;
    const name = await this.askName(row, current);
    label.hidden = false;
    if (name === undefined || name === current) {
      return;
    }
    const destination = `${parentOf(path)}/${name}`;
    const result = await this.host.move(path, destination);
    if (!result.ok) {
      this.showNotice(result.error === "exists" ? `${name} already exists.` : `${current} could not be renamed.`);
      return;
    }
    this.followMove(path, destination);
    await this.renderTree();
  }

  /** Points open files and expanded folders at their new paths after `from` became `to`. */
  private followMove(from: string, to: string): void {
    for (const folder of Array.from(this.expanded)) {
      const moved = movedPath(folder, from, to);
      if (moved !== undefined) {
        this.expanded.delete(folder);
        this.expanded.add(moved);
      }
    }
    for (const file of Array.from(this.files.values())) {
      const path = movedPath(file.path, from, to);
      if (path === undefined) {
        continue;
      }
      // A model is bound to its path, so the file gets a new one with the same text.
      const wasDirty = this.isDirty(file);
      const previous = file.model;
      const uri = monaco.Uri.file(path);
      const model = monaco.editor.getModel(uri) ?? monaco.editor.createModel(previous.getValue(), undefined, uri);
      if (model.getValue() !== previous.getValue()) {
        model.setValue(previous.getValue());
      }
      this.fileModels.keep(uri.toString());
      if (this.tabWidth !== undefined) {
        model.updateOptions({ tabSize: this.tabWidth });
      }
      this.files.delete(file.path);
      file.path = path;
      file.name = baseName(path);
      file.model = model;
      // No version of the new model matches the disk while there are unsaved edits.
      file.savedVersion = wasDirty ? -1 : model.getAlternativeVersionId();
      this.labelTab(file);
      model.onDidChangeContent(() => this.updateDirty(file));
      this.files.set(path, file);
      if (this.active === file) {
        const viewState = this.editor.saveViewState();
        this.editor.setModel(model);
        if (viewState) {
          this.editor.restoreViewState(viewState);
        }
      }
      this.fileModels.discard(previous.uri.toString(), previous);
      this.languageClients.ensureFor(path);
      this.updateDirty(file);
    }
    this.reportOpenFiles();
  }

  private async trash(path: string): Promise<void> {
    const result = await this.host.trash(path);
    if (!result.ok) {
      if (result.error !== "cancelled") {
        this.showNotice(`${baseName(path)} could not be ${this.remote ? "deleted" : "moved to the Trash"}.`);
      }
      return;
    }
    for (const folder of Array.from(this.expanded)) {
      if (isWithin(folder, path)) {
        this.expanded.delete(folder);
      }
    }
    for (const file of Array.from(this.files.values())) {
      if (isWithin(file.path, path)) {
        this.removeFile(file);
      }
    }
    await this.renderTree();
  }

  // Open files

  /** Reopens the files the folder had open when the app last ran. */
  private async restore(open: string[], active: string | undefined): Promise<void> {
    this.isRestoring = true;
    try {
      for (const path of open) {
        await this.loadFile(path, true);
      }
      const file = (active !== undefined ? this.files.get(active) : undefined) ?? this.files.values().next().value;
      if (file && !this.active) {
        this.activate(file, false);
      }
    } finally {
      this.isRestoring = false;
    }
    this.reportOpenFiles();
  }

  private reportOpenFiles(): void {
    if (this.isRestoring) {
      return;
    }
    const open = [...this.strip.children].map((tab) => (tab as HTMLElement).dataset.path ?? "");
    const active = this.active?.path ?? null;
    const report = JSON.stringify([open, active]);
    if (report !== this.reportedFiles) {
      this.reportedFiles = report;
      postToHost({ type: "projectFiles", open, active });
    }
  }

  private async openFile(path: string, position?: { line: number; column: number }): Promise<void> {
    const file = await this.loadFile(path);
    if (!file) {
      return;
    }
    this.activate(file);
    if (position) {
      reveal(this.editor, position.line, position.column);
    }
  }

  /**
   * Adds the file to the strip without showing it.
   * @param isQuiet Leaves out the notice when the file cannot be read.
   */
  private async loadFile(path: string, isQuiet = false): Promise<OpenFile | undefined> {
    const open = this.files.get(path);
    if (open) {
      return open;
    }
    const name = baseName(path);
    const result = await this.host.read(path);
    if (!result.ok || result.content === undefined) {
      if (!isQuiet) {
        this.showNotice(failureText(name, result.error));
      }
      return undefined;
    }
    const file = this.files.get(path) ?? this.addFile(path, name, result);
    this.reportOpenFiles();
    return file;
  }

  private addFile(path: string, name: string, result: FileResult): OpenFile {
    const uri = monaco.Uri.file(path);
    const content = result.content ?? "";
    // A model can exist already: the editor loads one to preview a file that is not open.
    const model = monaco.editor.getModel(uri) ?? monaco.editor.createModel(content, undefined, uri);
    if (model.getValue() !== content) {
      model.setValue(content);
    }
    this.fileModels.keep(uri.toString());
    if (this.tabWidth !== undefined) {
      model.updateOptions({ tabSize: this.tabWidth });
    }
    const tab = element("div", "project-tab");
    tab.append(element("span", "project-tab-name"), element("span", "project-tab-close", "×"));
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
    this.labelTab(file);
    model.onDidChangeContent(() => this.updateDirty(file));
    this.files.set(path, file);
    this.languageClients.ensureFor(path);
    return file;
  }

  private labelTab(file: OpenFile): void {
    file.tab.dataset.path = file.path;
    file.tab.title = file.path.startsWith(`${this.root}/`) ? file.path.slice(this.root.length + 1) : file.path;
    const label = file.tab.querySelector(".project-tab-name");
    if (label) {
      label.textContent = file.name;
    }
  }

  /** @param takesFocus False leaves the keyboard where it is. */
  private activate(file: OpenFile, takesFocus = true): void {
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
    if (takesFocus) {
      this.editor.focus();
    }
    if (isSwitch) {
      void this.reloadIfUnchanged(file);
      this.reportOpenFiles();
    }
  }

  /** Picks up a change made outside the editor, unless the file has unsaved edits here. */
  private async reloadIfUnchanged(file: OpenFile): Promise<void> {
    if (this.isDirty(file)) {
      return;
    }
    const result = await this.host.read(file.path);
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
    this.reportDirty();
  }

  /** Tells the host whether any open file has unsaved edits, when that changes. */
  private reportDirty(): void {
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
    const result = await this.host.write(file.path, file.model.getValue(), file.modified);
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
      const choice = await this.host.confirmClose(file.name);
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
    this.removeFile(file);
  }

  /** Takes the file off the strip, whatever state it is in. */
  private removeFile(file: OpenFile): void {
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
    this.fileModels.discard(file.model.uri.toString(), file.model);
    this.reportDirty();
    this.reportOpenFiles();
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
