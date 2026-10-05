import { postToHost, type CodeEditorHostMessage } from "../code-editor/bridge";
import { CodeEditor } from "../code-editor/codeEditor";
import codeEditorStyles from "../code-editor/styles.css?inline";
import { installWebviewStyles } from "./installWebviewStyles";

/**
 * Boots the code editor surface: one Monaco instance filling the page, driven
 * by the native host through `window.cmuxCodeEditor.receive`. Loaded as its own
 * chunk so the other surfaces never ship Monaco.
 */
export function mountCodeEditorSurface(rootElement: HTMLElement): void {
  installWebviewStyles("code-editor", codeEditorStyles);
  document.documentElement.dataset.cmuxWebviewKind = "code-editor";
  const editor = new CodeEditor(rootElement);
  (window as unknown as { cmuxCodeEditor: { receive(message: CodeEditorHostMessage): void } }).cmuxCodeEditor = {
    receive: (message) => editor.receive(message),
  };
  postToHost({ type: "ready" });
}
