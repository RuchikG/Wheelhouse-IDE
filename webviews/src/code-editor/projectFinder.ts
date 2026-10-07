import { findFiles } from "./fileFinder";

const MAXIMUM_RESULTS = 100;

export type FileIndex = { paths: string[]; isComplete: boolean };

/**
 * The field above the file tree that finds a file by name. While it holds
 * text, `list` shows the matches in place of the tree.
 */
export class FileFinder {
  readonly input = document.createElement("input");
  readonly list = document.createElement("div");
  private index: FileIndex = { paths: [], isComplete: true };
  private shown: string[] = [];
  private selected = 0;

  /**
   * @param loadIndex Lists the project's files as paths relative to its root.
   * @param open Opens the file at a relative path.
   * @param onSearchingChange Told when the field starts or stops holding text.
   */
  constructor(
    private readonly loadIndex: () => Promise<FileIndex>,
    private readonly open: (path: string) => void,
    private readonly onSearchingChange: (isSearching: boolean) => void,
  ) {
    this.input.className = "project-find";
    this.input.type = "search";
    this.input.placeholder = "Find file";
    this.input.spellcheck = false;
    this.list.className = "project-results";
    this.list.hidden = true;
    this.input.addEventListener("focus", () => void this.refresh());
    this.input.addEventListener("input", () => this.render());
    this.input.addEventListener("keydown", (event) => this.handleKey(event));
    this.list.addEventListener("click", (event) => {
      const row = (event.target as HTMLElement).closest<HTMLElement>(".project-result");
      if (row?.dataset.path) {
        this.pick(row.dataset.path);
      }
    });
  }

  focus(): void {
    this.input.focus();
    this.input.select();
  }

  clear(): void {
    if (this.input.value !== "") {
      this.input.value = "";
      this.render();
    }
  }

  /** Files come and go while the field is unused, so each visit lists them again. */
  private async refresh(): Promise<void> {
    this.index = await this.loadIndex();
    this.render();
  }

  private render(): void {
    const query = this.input.value.trim();
    const isSearching = query !== "";
    if (isSearching === this.list.hidden) {
      this.list.hidden = !isSearching;
      this.onSearchingChange(isSearching);
    }
    this.shown = findFiles(this.index.paths, query, MAXIMUM_RESULTS);
    this.selected = 0;
    const rows = this.shown.map((path, position) => {
      const row = document.createElement("div");
      row.className = position === 0 ? "project-result project-result-selected" : "project-result";
      row.dataset.path = path;
      const slash = path.lastIndexOf("/");
      const name = document.createElement("span");
      name.className = "project-result-name";
      name.textContent = path.slice(slash + 1);
      const folder = document.createElement("span");
      folder.className = "project-result-folder";
      folder.textContent = slash < 0 ? "" : path.slice(0, slash);
      row.append(name, folder);
      return row;
    });
    const note = document.createElement("div");
    note.className = "project-results-note";
    if (isSearching && rows.length === 0) {
      note.textContent = "No files match.";
    } else if (rows.length === MAXIMUM_RESULTS) {
      note.textContent = `Showing the first ${MAXIMUM_RESULTS} matches.`;
    } else if (!this.index.isComplete) {
      note.textContent = "This folder is too large to search in full.";
    }
    this.list.replaceChildren(...rows, ...(note.textContent ? [note] : []));
  }

  private handleKey(event: KeyboardEvent): void {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      this.select(this.selected + (event.key === "ArrowDown" ? 1 : -1));
    } else if (event.key === "Enter") {
      event.preventDefault();
      const path = this.shown[this.selected];
      if (path !== undefined) {
        this.pick(path);
      }
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.clear();
      this.input.blur();
    }
  }

  private select(position: number): void {
    if (this.shown.length === 0) {
      return;
    }
    const rows = this.list.querySelectorAll<HTMLElement>(".project-result");
    rows[this.selected]?.classList.remove("project-result-selected");
    this.selected = Math.max(0, Math.min(position, this.shown.length - 1));
    rows[this.selected]?.classList.add("project-result-selected");
    rows[this.selected]?.scrollIntoView({ block: "nearest" });
  }

  private pick(path: string): void {
    this.clear();
    this.open(path);
  }

}
