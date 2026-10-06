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
