import { expect, test } from "bun:test";
import { acceptUnopenedFiles, type ServerRange } from "../src/code-editor/unopenedFiles";

const range: ServerRange = { start: { line: 4, character: 5 }, end: { line: 4, character: 11 } };
const locate = (uri: string, at: ServerRange) => `${uri}:${at.start.line}`;

function bridgeKnowing(openURI: string) {
  return {
    translateBackRange(textDocument: { uri: string }, _range: ServerRange): string {
      if (textDocument.uri !== openURI) {
        throw new Error(`No text model for uri ${textDocument.uri}`);
      }
      return "open document";
    },
  };
}

test("a location in a file that is not open is located by its own URI", () => {
  const bridge = bridgeKnowing("file:///proj/a.go");
  expect(acceptUnopenedFiles(bridge, locate)).toBe(true);
  expect(bridge.translateBackRange({ uri: "file:///proj/B.go" }, range)).toBe("file:///proj/B.go:4");
});

test("a location in an open file still resolves through the open document", () => {
  const bridge = bridgeKnowing("file:///proj/a.go");
  acceptUnopenedFiles(bridge, locate);
  expect(bridge.translateBackRange({ uri: "file:///proj/a.go" }, range)).toBe("open document");
});

test("reports a client whose internals no longer match", () => {
  expect(acceptUnopenedFiles(undefined, locate)).toBe(false);
  expect(acceptUnopenedFiles({} as never, locate)).toBe(false);
});
