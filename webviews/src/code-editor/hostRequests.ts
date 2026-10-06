import { postToHost, type CodeEditorHostMessage, type FileResult } from "./bridge";

export type CloseChoice = "save" | "discard" | "cancel";

/** Questions the page puts to the native host, each answered by a later host message. */
export class HostRequests {
  private readonly pending = new Map<number, (result: unknown) => void>();
  private nextRequest = 1;

  /** Settles the request a host message answers. Returns false for any other message. */
  receive(message: CodeEditorHostMessage): boolean {
    if (message.type === "fsResult") {
      this.resolve(message.id, message);
      return true;
    }
    if (message.type === "confirmResult") {
      this.resolve(message.id, message.choice);
      return true;
    }
    return false;
  }

  list(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "list", path }));
  }

  read(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "read", path }));
  }

  write(path: string, content: string, modified: number | undefined): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "write", path, content, modified }));
  }

  createFile(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "createFile", path }));
  }

  createDirectory(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "createDirectory", path }));
  }

  move(path: string, to: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "move", path, to }));
  }

  /** The host asks before it moves anything to the Trash; `cancelled` is the error when the answer is no. */
  trash(path: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "trash", path }));
  }

  /** Every file of the project, as paths relative to `root`. */
  index(root: string): Promise<FileResult> {
    return this.request((id) => postToHost({ type: "fs", id, op: "index", path: root }));
  }

  confirmClose(name: string): Promise<CloseChoice> {
    return this.request((id) => postToHost({ type: "confirmClose", id, name }));
  }

  private resolve(id: number, result: unknown): void {
    const resolve = this.pending.get(id);
    this.pending.delete(id);
    resolve?.(result);
  }

  private request<Result>(send: (id: number) => void): Promise<Result> {
    const id = this.nextRequest++;
    return new Promise((resolve) => {
      this.pending.set(id, resolve as (result: unknown) => void);
      send(id);
    });
  }
}
