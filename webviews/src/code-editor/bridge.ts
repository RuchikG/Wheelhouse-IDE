import type { SearchMatch } from "./contentSearch";

/** Messages the native host sends through `window.cmuxCodeEditor.receive`. */
export type CodeEditorHostMessage =
  | { type: "document"; path: string; content: string; sequence: number; readOnly: boolean }
  | { type: "options"; options: CodeEditorOptions }
  | { type: "theme"; theme: CodeEditorTheme }
  | { type: "focus" }
  | { type: "requestSave" }
  | { type: "reveal"; line: number; column: number }
  | { type: "lspState"; server: string; state: "open" | "closed" | "unavailable" }
  | { type: "lsp"; server: string; message: unknown }
  | {
      type: "project";
      root: string;
      name: string;
      openFiles?: string[];
      activeFile?: string;
      /** The host that holds the folder, when it is not this machine. */
      remote?: string;
    }
  | ({ type: "fsResult"; id: number } & FileResult)
  | { type: "confirmResult"; id: number; choice: "save" | "discard" | "cancel" };

export type FileEntry = { name: string; isDirectory: boolean };

/** The host's answer to a `fs` request. `error` names why it failed. */
export type FileResult = {
  ok: boolean;
  entries?: FileEntry[];
  content?: string;
  modified?: number;
  readOnly?: boolean;
  /** For `index`: files as paths relative to the project root, and whether that is all of them. */
  paths?: string[];
  /** For `search`: the matching lines. `complete` is whether that is all of them, as for `index`. */
  matches?: SearchMatch[];
  complete?: boolean;
  error?: string;
};

export type FileOperation =
  | "list"
  | "read"
  | "write"
  | "createFile"
  | "createDirectory"
  | "move"
  | "trash"
  | "index"
  | "search";

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
  | { type: "lsp"; server: string; json: string }
  | {
      type: "fs";
      id: number;
      op: FileOperation;
      path: string;
      content?: string;
      modified?: number;
      to?: string;
      query?: string;
    }
  | { type: "projectFiles"; open: string[]; active: string | null }
  | { type: "confirmClose"; id: number; name: string }
  | { type: "projectDirty"; dirty: boolean };

type NativeMessageHandler = { postMessage(message: CodeEditorWebMessage): void };

export function postToHost(message: CodeEditorWebMessage): void {
  const handler = (
    window as unknown as {
      webkit?: { messageHandlers?: { cmuxCodeEditor?: NativeMessageHandler } };
    }
  ).webkit?.messageHandlers?.cmuxCodeEditor;
  handler?.postMessage(message);
}
