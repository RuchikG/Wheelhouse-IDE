import * as monaco from "monaco-editor";
import { postToHost } from "./bridge";

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

  readonly state: Transport["state"];

  constructor(private readonly server: string) {
    const transport = this;
    this.state = {
      get value() {
        return transport.current;
      },
      get onChange() {
        return (listener: Listener<ConnectionState>) => {
          transport.stateListeners.add(listener);
          return { dispose: () => transport.stateListeners.delete(listener) };
        };
      },
    };
  }

  send(message: Message): Promise<void> {
    this.restoreDocumentURICase(message);
    postToHost({ type: "lsp", server: this.server, json: JSON.stringify(message) });
    return Promise.resolve();
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

  receive(message: Message): void {
    if (this.listener) {
      this.listener(message);
    } else {
      this.unread.push(message);
    }
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

/**
 * One language client per kind of file, named by file extension. The host
 * decides whether a server exists for that kind and runs it.
 */
export class LanguageClients {
  private readonly transports = new Map<string, HostTransport>();
  private readonly requested = new Set<string>();

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
      const transport = new HostTransport(server);
      this.transports.set(server, transport);
      new monaco.lsp.MonacoLspClient(transport);
    } else if (state === "closed") {
      this.transports.get(server)?.close();
    }
  }

  receiveMessage(server: string, message: unknown): void {
    this.transports.get(server)?.receive(message as Message);
  }
}
