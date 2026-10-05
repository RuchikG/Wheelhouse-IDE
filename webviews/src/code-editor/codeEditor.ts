import * as monaco from "monaco-editor";
import {
  postToHost,
  type CodeEditorHostMessage,
  type CodeEditorOptions,
  type CodeEditorTheme,
} from "./bridge";

const THEME_NAME = "cmux-host";
const CHANGE_DEBOUNCE_MS = 120;

// This module lands in `chunks/codeEditorSurface.mjs`; the worker entry is
// emitted next to it.
const editorWorkerURL = new URL(/* @vite-ignore */ "./monaco-editor-worker.mjs", import.meta.url);

(globalThis as { MonacoEnvironment?: monaco.Environment }).MonacoEnvironment = {
  getWorker: () => new Worker(editorWorkerURL, { type: "module" }),
};

/**
 * Owns the Monaco instance for one file and keeps it in sync with the native
 * host: the host pushes documents, options and theme, and the editor reports
 * edits and save requests back.
 */
export class CodeEditor {
  private readonly editor: monaco.editor.IStandaloneCodeEditor;
  private documentSequence = 0;
  private applyingHostDocument = false;
  private pendingChange: ReturnType<typeof setTimeout> | undefined;
  private tabWidth: number | undefined;

  constructor(container: HTMLElement) {
    this.editor = monaco.editor.create(container, {
      automaticLayout: true,
      fontFamily: 'ui-monospace, "SF Mono", Menlo, monospace',
      fontSize: 13,
      scrollBeyondLastLine: false,
      stickyScroll: { enabled: false },
    });
    this.editor.onDidChangeModelContent(() => {
      if (!this.applyingHostDocument) {
        this.scheduleChange();
      }
    });
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => this.save());
  }

  receive(message: CodeEditorHostMessage): void {
    switch (message.type) {
      case "document":
        this.applyDocument(message.path, message.content, message.sequence, message.readOnly);
        break;
      case "options":
        this.applyOptions(message.options);
        break;
      case "theme":
        this.applyTheme(message.theme);
        break;
      case "focus":
        this.editor.focus();
        break;
      case "requestSave":
        this.save();
        break;
    }
  }

  private applyDocument(path: string, content: string, sequence: number, readOnly: boolean): void {
    this.cancelPendingChange();
    this.documentSequence = sequence;
    this.editor.updateOptions({ readOnly });
    const uri = monaco.Uri.file(path);
    const current = this.editor.getModel();
    this.applyingHostDocument = true;
    try {
      if (current && current.uri.toString() === uri.toString()) {
        if (current.getValue() !== content) {
          const viewState = this.editor.saveViewState();
          current.setValue(content);
          if (viewState) {
            this.editor.restoreViewState(viewState);
          }
        }
        return;
      }
      const model = monaco.editor.getModel(uri) ?? monaco.editor.createModel(content, undefined, uri);
      if (model.getValue() !== content) {
        model.setValue(content);
      }
      if (this.tabWidth !== undefined) {
        model.updateOptions({ tabSize: this.tabWidth });
      }
      this.editor.setModel(model);
      current?.dispose();
    } finally {
      this.applyingHostDocument = false;
    }
  }

  private applyOptions(options: CodeEditorOptions): void {
    this.editor.updateOptions({
      wordWrap: options.wordWrap ? "on" : "off",
      lineNumbers: options.lineNumbers ? "on" : "off",
      guides: { indentation: options.indentGuides },
      renderLineHighlight: options.currentLineHighlight ? "line" : "none",
      fontSize: options.fontSize,
    });
    this.tabWidth = options.tabWidth;
    this.editor.getModel()?.updateOptions({ tabSize: options.tabWidth });
  }

  private applyTheme(theme: CodeEditorTheme): void {
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

  private scheduleChange(): void {
    this.cancelPendingChange();
    this.pendingChange = setTimeout(() => {
      this.pendingChange = undefined;
      postToHost({ type: "change", content: this.editor.getValue(), sequence: this.documentSequence });
    }, CHANGE_DEBOUNCE_MS);
  }

  private cancelPendingChange(): void {
    if (this.pendingChange !== undefined) {
      clearTimeout(this.pendingChange);
      this.pendingChange = undefined;
    }
  }

  private save(): void {
    this.cancelPendingChange();
    postToHost({ type: "save", content: this.editor.getValue(), sequence: this.documentSequence });
  }
}
