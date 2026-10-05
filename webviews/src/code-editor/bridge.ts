/** Messages the native host sends through `window.cmuxCodeEditor.receive`. */
export type CodeEditorHostMessage =
  | { type: "document"; path: string; content: string; sequence: number; readOnly: boolean }
  | { type: "options"; options: CodeEditorOptions }
  | { type: "theme"; theme: CodeEditorTheme }
  | { type: "focus" }
  | { type: "requestSave" }
  | { type: "reveal"; line: number; column: number }
  | { type: "lspState"; server: string; state: "open" | "closed" | "unavailable" }
  | { type: "lsp"; server: string; message: unknown };

export type CodeEditorOptions = {
  wordWrap: boolean;
  lineNumbers: boolean;
  indentGuides: boolean;
  currentLineHighlight: boolean;
  tabWidth: number;
  fontSize: number;
};

export type CodeEditorTheme = {
  isDark: boolean;
  /** `#RRGGBB` or `#RRGGBBAA`. */
  background: string;
  foreground: string;
};

/** Messages posted to the native `cmuxCodeEditor` script message handler. */
export type CodeEditorWebMessage =
  | { type: "ready" }
  | { type: "change"; content: string; sequence: number }
  | { type: "save"; content: string; sequence: number }
  | { type: "openFile"; path: string; line: number; column: number }
  | { type: "lspStart"; server: string }
  | { type: "lsp"; server: string; json: string };

type NativeMessageHandler = { postMessage(message: CodeEditorWebMessage): void };

export function postToHost(message: CodeEditorWebMessage): void {
  const handler = (
    window as unknown as {
      webkit?: { messageHandlers?: { cmuxCodeEditor?: NativeMessageHandler } };
    }
  ).webkit?.messageHandlers?.cmuxCodeEditor;
  handler?.postMessage(message);
}
