import * as monaco from "monaco-editor";
import type { CodeEditorOptions, CodeEditorTheme, FileResult } from "./bridge";
import { FileModels } from "./fileModels";

const THEME_NAME = "cmux-host";

// This module lands in the same chunk as the editor surface; the worker entry
// is emitted next to it.
const editorWorkerURL = new URL(/* @vite-ignore */ "./monaco-editor-worker.mjs", import.meta.url);

(globalThis as { MonacoEnvironment?: monaco.Environment }).MonacoEnvironment = {
  getWorker: () => new Worker(editorWorkerURL, { type: "module" }),
};

export type EditorFileModels = FileModels<monaco.editor.ITextModel>;

/** Models for files the editor shows without the page having opened them, read through the host. */
export function createFileModels(read: (path: string) => Promise<FileResult>): EditorFileModels {
  return new FileModels({
    find: (uri) => monaco.editor.getModel(monaco.Uri.parse(uri)) ?? undefined,
    create: (uri, content) => monaco.editor.createModel(content, undefined, monaco.Uri.parse(uri)),
    read: async (uri) => {
      const file = monaco.Uri.parse(uri);
      if (file.scheme !== "file") {
        return undefined;
      }
      const result = await read(file.fsPath);
      return result.ok ? result.content : undefined;
    },
  });
}

/**
 * Creates the page's editor. Monaco takes replacement services only with the
 * first editor it creates, so nothing else may touch Monaco before this.
 */
export function createMonacoEditor(
  container: HTMLElement,
  fileModels: EditorFileModels,
): monaco.editor.IStandaloneCodeEditor {
  return monaco.editor.create(
    container,
    {
      automaticLayout: true,
      fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
      fontSize: 13,
      scrollBeyondLastLine: false,
      stickyScroll: { enabled: false },
    },
    { textModelService: fileModels },
  );
}

/** A short message beside the cursor, the way Monaco reports a refused rename. */
export function showMessageAtCursor(editor: monaco.editor.IStandaloneCodeEditor, text: string): void {
  const position = editor.getPosition();
  const messages = editor.getContribution("editor.contrib.messageController") as {
    showMessage?(message: string, position: monaco.IPosition): void;
  } | null;
  if (position && typeof messages?.showMessage === "function") {
    messages.showMessage(text, position);
  }
}

export function applyEditorOptions(editor: monaco.editor.IStandaloneCodeEditor, options: CodeEditorOptions): void {
  editor.updateOptions({
    wordWrap: options.wordWrap ? "on" : "off",
    lineNumbers: options.lineNumbers ? "on" : "off",
    guides: { indentation: options.indentGuides },
    renderLineHighlight: options.currentLineHighlight ? "line" : "none",
    fontSize: options.fontSize,
  });
}

export function applyEditorTheme(theme: CodeEditorTheme): void {
  monaco.editor.defineTheme(THEME_NAME, {
    base: theme.isDark ? "vs-dark" : "vs",
    inherit: true,
    rules: [],
    colors: {
      "editor.background": theme.background,
      "editor.foreground": theme.foreground,
      "editorGutter.background": theme.background,
      "minimap.background": theme.background,
    },
  });
  monaco.editor.setTheme(THEME_NAME);
  document.documentElement.style.colorScheme = theme.isDark ? "dark" : "light";
}

/** Line and column of a position or the start of a selection; 1,1 when absent. */
export function startOf(target: monaco.IRange | monaco.IPosition | undefined): { line: number; column: number } {
  if (target && "lineNumber" in target) {
    return { line: target.lineNumber, column: target.column };
  }
  if (target) {
    return { line: target.startLineNumber, column: target.startColumn };
  }
  return { line: 1, column: 1 };
}

export function reveal(editor: monaco.editor.IStandaloneCodeEditor, line: number, column: number): void {
  const position = { lineNumber: line, column };
  editor.setPosition(position);
  editor.revealPositionInCenter(position);
  editor.focus();
}
