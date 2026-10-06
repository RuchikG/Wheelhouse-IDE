import * as monaco from "monaco-editor";
import type { CodeEditorOptions, CodeEditorTheme } from "./bridge";

const THEME_NAME = "cmux-host";

// This module lands in the same chunk as the editor surface; the worker entry
// is emitted next to it.
const editorWorkerURL = new URL(/* @vite-ignore */ "./monaco-editor-worker.mjs", import.meta.url);

(globalThis as { MonacoEnvironment?: monaco.Environment }).MonacoEnvironment = {
  getWorker: () => new Worker(editorWorkerURL, { type: "module" }),
};

export function createMonacoEditor(container: HTMLElement): monaco.editor.IStandaloneCodeEditor {
  return monaco.editor.create(container, {
    automaticLayout: true,
    fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
    fontSize: 13,
    scrollBeyondLastLine: false,
    stickyScroll: { enabled: false },
  });
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
