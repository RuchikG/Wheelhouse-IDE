import * as monaco from "monaco-editor";
import { postToHost } from "./bridge";
import {
  acceptUnopenedFiles,
  editedFiles,
  forgetVersionsOf,
  type DocumentBridge,
  type ServerRange,
} from "./unopenedFiles";

type Transport = ConstructorParameters<typeof monaco.lsp.MonacoLspClient>[0];
type Message = Parameters<Transport["send"]>[0];
type ConnectionState = Transport["state"]["value"];
type Listener<T> = (value: T) => void;

/**
 * Carries JSON-RPC messages between Monaco's language client and a language
 * server the native host runs. Messages cross the bridge as JSON text so
 * integers stay integers on the native side.
 */
class HostTransport implements Transport {
  private listener: Listener<Message> | undefined;
  private readonly unread: Message[] = [];
  private current: ConnectionState = { state: "open" };
  private readonly stateListeners = new Set<Listener<ConnectionState>>();
  /** Lowercased document URI to the URI as the file system spells it. */
  private readonly documentURIs = new Map<string, string>();
  /** Ids of the rename requests that are waiting for their answer. */
  private readonly renames = new Set<unknown>();
  /** Settles when every message received so far has been handed to the client. */
  private delivered: Promise<void> = Promise.resolve();

  readonly state: Transport["state"];

  constructor(
    private readonly server: string,
    private readonly openForEdit: OpenForEdit,
  ) {
    this.state = Object.defineProperties(
      {},
      {
        value: { get: () => this.current },
        onChange: {
          get: () => (listener: Listener<ConnectionState>) => {
            this.stateListeners.add(listener);
            return { dispose: () => this.stateListeners.delete(listener) };
          },
        },
      },
    ) as Transport["state"];
  }

  send(message: Message): Promise<void> {
    if (this.answerForOtherKindOfFile(message)) {
      return Promise.resolve();
    }
    this.restoreDocumentURICase(message);
    const request = message as { id?: unknown; method?: string };
    if (request.method === "textDocument/rename" && request.id !== undefined) {
      this.renames.add(request.id);
    }
    postToHost({ type: "lsp", server: this.server, json: JSON.stringify(message) });
    return Promise.resolve();
  }

  /**
   * Monaco's client reports every open file to every server. Whatever concerns
   * a file of another kind stays here: notifications are dropped and requests
   * answered with no result.
   */
  private answerForOtherKindOfFile(message: Message): boolean {
    const outgoing = message as { id?: unknown; method?: string; params?: { textDocument?: { uri?: string } } };
    const uri = outgoing.params?.textDocument?.uri;
    if (typeof uri !== "string" || typeof outgoing.method !== "string") {
      return false;
    }
    const path = uri.split(/[?#]/)[0];
    if (path.toLowerCase().endsWith(`.${this.server}`)) {
      return false;
    }
    if (outgoing.id !== undefined) {
      this.receive({ jsonrpc: "2.0", id: outgoing.id, result: null } as unknown as Message);
    }
    return true;
  }

  /**
   * Monaco's client lowercases the URI in document open, change and close
   * notifications. A server that maps files to packages by path (gopls) then
   * treats the document as a stray file, so the real spelling is put back.
   */
  private restoreDocumentURICase(message: Message): void {
    const notification = message as { method?: string; params?: { textDocument?: { uri?: string } } };
    const textDocument = notification.params?.textDocument;
    if (!notification.method?.startsWith("textDocument/did") || typeof textDocument?.uri !== "string") {
      return;
    }
    const lowercased = textDocument.uri;
    let uri = this.documentURIs.get(lowercased);
    if (uri === undefined) {
      uri = monaco.editor
        .getModels()
        .map((model) => model.uri.toString(true))
        .find((candidate) => candidate.toLowerCase() === lowercased);
      if (uri === undefined) {
        return;
      }
      this.documentURIs.set(lowercased, uri);
    }
    textDocument.uri = uri;
    if (notification.method === "textDocument/didClose") {
      this.documentURIs.delete(lowercased);
    }
  }

  setListener(listener: Listener<Message> | undefined): void {
    this.listener = listener;
    while (this.listener && this.unread.length > 0) {
      this.listener(this.unread.shift() as Message);
    }
  }

  /**
   * Hands a server message to the client, in arrival order. The answer to a
   * rename first waits until the page holds every file it edits: Monaco applies
   * edits to the models it has, and the page must be able to save them. When a
   * file cannot be held the rename is given no result, because applying the
   * rest would change some files and not others.
   */
  receive(message: Message): void {
    this.delivered = this.delivered.then(async () => {
      const answer = message as { id?: unknown; method?: string; result?: unknown };
      if (answer.method === undefined && this.renames.delete(answer.id)) {
        const unopened = new Set<string>();
        let isHeld = true;
        for (const uri of editedFiles(answer)) {
          const file = monaco.Uri.parse(uri);
          if (!monaco.editor.getModel(file)) {
            unopened.add(uri);
          }
          isHeld = (await this.openForEdit(file).catch(() => false)) && isHeld;
        }
        forgetVersionsOf(answer, unopened);
        if (!isHeld) {
          answer.result = null;
        }
      }
      if (this.listener) {
        this.listener(message);
      } else {
        this.unread.push(message);
      }
    });
  }

  close(): void {
    this.current = { state: "closed", error: undefined };
    for (const listener of this.stateListeners) {
      listener(this.current);
    }
  }

  toString(): string {
    return `host language server (${this.server})`;
  }
}

/** Makes sure the page holds a file a rename edits. False when it cannot. */
export type OpenForEdit = (file: monaco.Uri) => Promise<boolean>;

/** Where an answer points when its file has no open document: the answer's own URI. */
function locateUnopenedFile(uri: string, range: ServerRange) {
  return {
    textModel: { uri: monaco.Uri.parse(uri) },
    range: new monaco.Range(range.start.line + 1, range.start.character + 1, range.end.line + 1, range.end.character + 1),
  };
}

/**
 * One language client per kind of file, named by file extension. The host
 * decides whether a server exists for that kind and runs it.
 */
export class LanguageClients {
  private readonly transports = new Map<string, HostTransport>();
  private readonly requested = new Set<string>();

  constructor(private readonly openForEdit: OpenForEdit) {}

  /** Asks the host for the server that handles `path`, once per kind of file. */
  ensureFor(path: string): void {
    const name = path.slice(path.lastIndexOf("/") + 1);
    const dot = name.lastIndexOf(".");
    if (dot <= 0) {
      return;
    }
    const server = name.slice(dot + 1).toLowerCase();
    if (this.requested.has(server)) {
      return;
    }
    this.requested.add(server);
    postToHost({ type: "lspStart", server });
  }

  receiveState(server: string, state: "open" | "closed" | "unavailable"): void {
    if (state === "open" && !this.transports.has(server)) {
      const transport = new HostTransport(server, this.openForEdit);
      this.transports.set(server, transport);
      const client = new monaco.lsp.MonacoLspClient(transport);
      const bridge = (client as unknown as { _bridge?: DocumentBridge<ReturnType<typeof locateUnopenedFile>> })._bridge;
      if (!acceptUnopenedFiles(bridge, locateUnopenedFile)) {
        console.error("code editor: language client internals changed; jumps to unopened files will fail");
      }
    } else if (state === "closed") {
      this.transports.get(server)?.close();
    }
  }

  receiveMessage(server: string, message: unknown): void {
    this.transports.get(server)?.receive(message as Message);
  }
}
