import { excerpt, groupByFile, MINIMUM_TYPED_QUERY, searchNote, type SearchMatch } from "./contentSearch";

const TYPING_PAUSE = 250;

export type SearchResults = { matches: SearchMatch[]; isComplete: boolean };

/**
 * The field above the file tree that searches inside the project's files.
 * While it holds text, `list` shows the matching lines in place of the tree,
 * and stays until the field is cleared, so that one match after another can
 * be opened.
 */
export class ContentSearch {
  readonly input = document.createElement("input");
  readonly list = document.createElement("div");
  private shown: SearchMatch[] = [];
  private selected = -1;
  private latest = 0;
  private timer: ReturnType<typeof setTimeout> | undefined;

  /**
   * @param search Finds the lines that contain a text.
   * @param open Opens a match in the editor.
   * @param onSearchingChange Told when the field starts or stops holding text.
   */
  constructor(
    private readonly search: (query: string) => Promise<SearchResults>,
    private readonly open: (match: SearchMatch) => void,
    private readonly onSearchingChange: (isSearching: boolean) => void,
  ) {
    this.input.className = "project-find";
    this.input.type = "search";
    this.input.placeholder = "Search in files";
    this.input.spellcheck = false;
    this.list.className = "project-results";
    this.list.hidden = true;
    this.input.addEventListener("input", () => this.typed());
    this.input.addEventListener("keydown", (event) => this.handleKey(event));
    this.list.addEventListener("click", (event) => {
      const row = (event.target as HTMLElement).closest<HTMLElement>("[data-match]");
      if (row?.dataset.match !== undefined) {
        this.pick(Number(row.dataset.match));
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
      this.typed();
    }
  }

  private typed(): void {
    this.cancelTimer();
    const isSearching = this.input.value !== "";
    if (isSearching === this.list.hidden) {
      this.list.hidden = !isSearching;
      this.onSearchingChange(isSearching);
    }
    if (!isSearching) {
      this.latest += 1;
      this.show([], undefined);
    } else if (this.input.value.trim().length >= MINIMUM_TYPED_QUERY) {
      this.timer = setTimeout(() => void this.run(), TYPING_PAUSE);
    }
  }

  private cancelTimer(): void {
    if (this.timer !== undefined) {
      clearTimeout(this.timer);
      this.timer = undefined;
    }
  }

  private async run(): Promise<void> {
    this.cancelTimer();
    const query = this.input.value;
    if (query.trim() === "") {
      return;
    }
    const request = ++this.latest;
    if (this.shown.length === 0) {
      this.show([], "Searching…");
    }
    const results = await this.search(query);
    // An answer to a text that has been typed over since.
    if (request === this.latest) {
      this.show(results.matches, searchNote(results.matches.length, results.isComplete));
    }
  }

  private show(matches: SearchMatch[], note: string | undefined): void {
    this.shown = matches;
    this.selected = -1;
    const rows: HTMLElement[] = [];
    let position = 0;
    for (const file of groupByFile(matches)) {
      const slash = file.path.lastIndexOf("/");
      const header = document.createElement("div");
      header.className = "project-result project-search-file";
      header.dataset.match = String(position);
      header.title = file.path;
      const name = document.createElement("span");
      name.className = "project-result-name";
      name.textContent = file.path.slice(slash + 1);
      const folder = document.createElement("span");
      folder.className = "project-result-folder";
      folder.textContent = slash < 0 ? "" : file.path.slice(0, slash);
      const count = document.createElement("span");
      count.className = "project-search-count";
      count.textContent = String(file.matches.length);
      header.append(name, folder, count);
      rows.push(header);
      for (const match of file.matches) {
        const row = document.createElement("div");
        row.className = "project-result project-search-match";
        row.dataset.match = String(position);
        position += 1;
        const line = document.createElement("span");
        line.className = "project-search-line";
        line.textContent = String(match.line);
        const text = document.createElement("span");
        text.className = "project-search-text";
        const parts = excerpt(match);
        const hit = document.createElement("mark");
        hit.textContent = parts.hit;
        text.append(parts.before, hit, parts.after);
        row.append(line, text);
        rows.push(row);
      }
    }
    if (note !== undefined) {
      const line = document.createElement("div");
      line.className = "project-results-note";
      line.textContent = note;
      rows.push(line);
    }
    this.list.replaceChildren(...rows);
  }

  private handleKey(event: KeyboardEvent): void {
    if (event.key === "ArrowDown" || event.key === "ArrowUp") {
      event.preventDefault();
      this.select(this.selected + (event.key === "ArrowDown" ? 1 : -1));
    } else if (event.key === "Enter") {
      event.preventDefault();
      if (this.timer !== undefined || this.shown.length === 0) {
        void this.run();
      } else {
        this.pick(Math.max(this.selected, 0));
      }
    } else if (event.key === "Escape") {
      event.preventDefault();
      this.clear();
      this.input.blur();
    }
  }

  private matchRows(): HTMLElement[] {
    return [...this.list.querySelectorAll<HTMLElement>(".project-search-match")];
  }

  private select(position: number): void {
    if (this.shown.length === 0) {
      return;
    }
    const rows = this.matchRows();
    rows[this.selected]?.classList.remove("project-result-selected");
    this.selected = Math.max(0, Math.min(position, this.shown.length - 1));
    rows[this.selected]?.classList.add("project-result-selected");
    rows[this.selected]?.scrollIntoView({ block: "nearest" });
  }

  private pick(position: number): void {
    const match = this.shown[position];
    if (match) {
      this.select(position);
      this.open(match);
    }
  }
}
