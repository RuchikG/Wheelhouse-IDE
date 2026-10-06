export type ModelStore<Model> = {
  /** The model for `uri`, when one exists. */
  find(uri: string): Model | undefined;
  create(uri: string, content: string): Model;
  /** The file's text; undefined when it cannot be shown. */
  read(uri: string): Promise<string | undefined>;
};

export type ModelReference<Model> = { object: { textEditorModel: Model }; dispose(): void };

type Entry<Model> = {
  model: Model;
  references: number;
  /** The page shows this file itself, so the model outlives its references. */
  kept: boolean;
};

/**
 * Monaco's text model service: what the editor asks for the text of a file it
 * wants to show beside the current one (the preview of a definition, a row of
 * the references list). The stock service only knows models that already
 * exist; this one reads the file and drops its model when the last reference
 * is released.
 */
export class FileModels<Model extends { dispose(): void }> {
  private readonly entries = new Map<string, Entry<Model>>();
  private readonly loading = new Map<string, Promise<void>>();

  constructor(private readonly store: ModelStore<Model>) {}

  async createModelReference(resource: { toString(): string }): Promise<ModelReference<Model>> {
    const uri = resource.toString();
    if (!this.entries.has(uri) && !this.store.find(uri)) {
      await this.load(uri);
    }
    let entry = this.entries.get(uri);
    if (!entry) {
      const model = this.store.find(uri);
      if (!model) {
        throw new Error("Model not found");
      }
      entry = { model, references: 0, kept: true };
      this.entries.set(uri, entry);
    }
    const held = entry;
    held.references += 1;
    let released = false;
    return {
      object: { textEditorModel: held.model },
      dispose: () => {
        if (!released) {
          released = true;
          this.release(uri, held);
        }
      },
    };
  }

  /** The page opened this file: its model stays when the references go. */
  keep(uri: string): void {
    const entry = this.entries.get(uri);
    if (entry) {
      entry.kept = true;
    }
  }

  /** The page closed this file: its model goes now, or with the last reference to it. */
  discard(uri: string, model: Model): void {
    const entry = this.entries.get(uri);
    if (entry && entry.model === model) {
      entry.kept = false;
    } else {
      model.dispose();
    }
  }

  private load(uri: string): Promise<void> {
    let pending = this.loading.get(uri);
    if (!pending) {
      pending = this.store
        .read(uri)
        .then((content) => {
          if (content !== undefined && !this.store.find(uri)) {
            this.entries.set(uri, { model: this.store.create(uri, content), references: 0, kept: false });
          }
        })
        .finally(() => this.loading.delete(uri));
      this.loading.set(uri, pending);
    }
    return pending;
  }

  private release(uri: string, entry: Entry<Model>): void {
    entry.references -= 1;
    if (entry.references > 0) {
      return;
    }
    this.entries.delete(uri);
    if (!entry.kept) {
      entry.model.dispose();
    }
  }
}
