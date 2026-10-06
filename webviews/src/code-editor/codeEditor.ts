import * as monaco from "monaco-editor";
import { postToHost, type CodeEditorHostMessage, type CodeEditorOptions } from "./bridge";
import {
  applyEditorOptions,
  applyEditorTheme,
  createFileModels,
  createMonacoEditor,
  reveal,
  showMessageAtCursor,
  startOf,
} from "./editorChrome";
import { HostRequests } from "./hostRequests";
import { LanguageClients } from "./languageClient";

const CHANGE_DEBOUNCE_MS = 120;

/**
 * Owns the Monaco instance for one file and keeps it in sync with the native
 * host: the host pushes documents, options and theme, and the editor reports
 * edits and save requests back.
 */
export class CodeEditor {
  private readonly editor: monaco.editor.IStandaloneCodeEditor;
  private readonly host = new HostRequests();
  private readonly fileModels = createFileModels((path) => this.host.read(path));
  // This page holds one file, so a rename that reaches into another cannot be applied here.
  private readonly languageClients = new LanguageClients(async (file) => {
    if (file.toString() === this.editor.getModel()?.uri.toString()) {
      return true;
    }
    showMessageAtCursor(this.editor, "This also changes other files. Open the folder in an editor tab to apply it.");
    return false;
  });
  private documentSequence = 0;
  private applyingHostDocument = false;
  private pendingChange: ReturnType<typeof setTimeout> | undefined;
  private tabWidth: number | undefined;

  constructor(container: HTMLElement) {
    this.editor = createMonacoEditor(container, this.fileModels);
    this.editor.onDidChangeModelContent(() => {
      if (!this.applyingHostDocument) {
        this.scheduleChange();
      }
    });
    this.editor.addCommand(monaco.KeyMod.CtrlCmd | monaco.KeyCode.KeyS, () => this.save());
    // A jump to another file (go to definition, a reference) is the host's to show.
    monaco.editor.registerEditorOpener({
      openCodeEditor: (_source, resource, selectionOrPosition) => {
        if (resource.scheme !== "file") {
          return false;
        }
        postToHost({ type: "openFile", path: resource.fsPath, ...startOf(selectionOrPosition) });
        return true;
      },
    });
  }

  receive(message: CodeEditorHostMessage): void {
    if (this.host.receive(message)) {
      return;
    }
    switch (message.type) {
      case "document":
        this.applyDocument(message.path, message.content, message.sequence, message.readOnly);
        break;
      case "options":
        this.applyOptions(message.options);
        break;
      case "theme":
        applyEditorTheme(message.theme);
        break;
      case "focus":
        this.editor.focus();
        break;
      case "requestSave":
        this.save();
        break;
      case "reveal":
        reveal(this.editor, message.line, message.column);
        break;
      case "lspState":
        this.languageClients.receiveState(message.server, message.state);
        break;
      case "lsp":
        this.languageClients.receiveMessage(message.server, message.message);
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
      this.fileModels.keep(uri.toString());
      this.editor.setModel(model);
      if (current) {
        this.fileModels.discard(current.uri.toString(), current);
      }
      this.languageClients.ensureFor(path);
    } finally {
      this.applyingHostDocument = false;
    }
  }

  private applyOptions(options: CodeEditorOptions): void {
    applyEditorOptions(this.editor, options);
    this.tabWidth = options.tabWidth;
    this.editor.getModel()?.updateOptions({ tabSize: options.tabWidth });
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
