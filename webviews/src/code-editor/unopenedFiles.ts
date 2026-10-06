export type ServerRange = { start: { line: number; character: number }; end: { line: number; character: number } };

export type DocumentBridge<Translated> = {
  translateBackRange(textDocument: { uri: string }, range: ServerRange): Translated;
};

/**
 * Monaco's language client resolves the file a server answer names through its
 * table of open documents and throws for any other file, which loses a
 * definition or reference in a file that is not open. `locate` answers for
 * those files instead. Returns false when the client no longer has this shape.
 */
export function acceptUnopenedFiles<Translated>(
  bridge: DocumentBridge<Translated> | undefined,
  locate: (uri: string, range: ServerRange) => Translated,
): boolean {
  if (typeof bridge?.translateBackRange !== "function") {
    return false;
  }
  const translateOpenDocument = bridge.translateBackRange.bind(bridge);
  bridge.translateBackRange = (textDocument, range) => {
    try {
      return translateOpenDocument(textDocument, range);
    } catch {
      return locate(textDocument.uri, range);
    }
  };
  return true;
}

type WorkspaceEdit = {
  changes?: Record<string, unknown>;
  documentChanges?: { textDocument?: { uri?: string; version?: number | null } }[];
};

function workspaceEdit(answer: unknown): WorkspaceEdit {
  const result = (answer as { result?: unknown } | null)?.result;
  return typeof result === "object" && result !== null ? (result as WorkspaceEdit) : {};
}

/** URIs of the files the answer to a rename edits. */
export function editedFiles(answer: unknown): string[] {
  const edit = workspaceEdit(answer);
  const uris = new Set<string>();
  if (typeof edit.changes === "object" && edit.changes !== null) {
    for (const uri of Object.keys(edit.changes)) {
      uris.add(uri);
    }
  }
  for (const change of Array.isArray(edit.documentChanges) ? edit.documentChanges : []) {
    if (typeof change?.textDocument?.uri === "string") {
      uris.add(change.textDocument.uri);
    }
  }
  return [...uris];
}

/**
 * Clears, in place, the document version a rename answer gives for each file
 * in `unopened`. A server numbers a file it was never sent itself (gopls says
 * 0), and Monaco refuses an edit whose version differs from the model's.
 */
export function forgetVersionsOf(answer: unknown, unopened: ReadonlySet<string>): void {
  const edit = workspaceEdit(answer);
  for (const change of Array.isArray(edit.documentChanges) ? edit.documentChanges : []) {
    if (typeof change?.textDocument?.uri === "string" && unopened.has(change.textDocument.uri)) {
      change.textDocument.version = null;
    }
  }
}
