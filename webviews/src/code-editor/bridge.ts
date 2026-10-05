/** Messages the native host sends through `window.cmuxCodeEditor.receive`. */
export type CodeEditorHostMessage =
  | { type: "document"; path: string; content: string; sequence: number; readOnly: boolean }
  | { type: "options"; options: CodeEditorOptions }
  | { type: "theme"; theme: CodeEditorTheme }
  | { type: "focus" }
  | { type: "requestSave" };

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
  | { type: "save"; content: string; sequence: number };

type NativeMessageHandler = { postMessage(message: CodeEditorWebMessage): void };

export function postToHost(message: CodeEditorWebMessage): void {
  const handler = (
    window as unknown as {
      webkit?: { messageHandlers?: { cmuxCodeEditor?: NativeMessageHandler } };
    }
  ).webkit?.messageHandlers?.cmuxCodeEditor;
  handler?.postMessage(message);
}
