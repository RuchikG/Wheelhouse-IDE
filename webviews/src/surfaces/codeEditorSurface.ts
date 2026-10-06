import { postToHost, type CodeEditorHostMessage } from "../code-editor/bridge";
import { CodeEditor } from "../code-editor/codeEditor";
import { ProjectEditor } from "../code-editor/projectEditor";
import codeEditorStyles from "../code-editor/styles.css?inline";
import { installWebviewStyles } from "./installWebviewStyles";

/**
 * Boots the code editor surface: Monaco filling the page, driven by the native
 * host through `window.cmuxCodeEditor.receive`. The host's first `document` or
 * `project` message decides whether the page edits one file or shows a folder.
 * Loaded as its own chunk so the other surfaces never ship Monaco.
 */
export function mountCodeEditorSurface(rootElement: HTMLElement): void {
  installWebviewStyles("code-editor", codeEditorStyles);
  document.documentElement.dataset.cmuxWebviewKind = "code-editor";
  let editor: CodeEditor | ProjectEditor | undefined;
  const early: CodeEditorHostMessage[] = [];
  (window as unknown as { cmuxCodeEditor: { receive(message: CodeEditorHostMessage): void } }).cmuxCodeEditor = {
    receive: (message) => {
      if (!editor) {
        if (message.type === "document") {
          editor = new CodeEditor(rootElement);
        } else if (message.type === "project") {
          editor = new ProjectEditor(rootElement);
        } else {
          early.push(message);
          return;
        }
        for (const earlier of early.splice(0)) {
          editor.receive(earlier);
        }
      }
      editor.receive(message);
    },
  };
  postToHost({ type: "ready" });
}
