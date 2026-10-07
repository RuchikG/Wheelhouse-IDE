import { expect, test } from "bun:test";
import { excerpt, groupByFile, searchNote, type SearchMatch } from "../src/code-editor/contentSearch";

function match(path: string, line: number, text: string, hit: string): SearchMatch {
  const matchStart = text.indexOf(hit);
  return { path, line, column: matchStart + 1, text, matchStart, matchLength: hit.length };
}

test("groups the matches by file in the order they came", () => {
  const matches = [match("a.go", 1, "x", "x"), match("a.go", 9, "x", "x"), match("pkg/b.go", 2, "x", "x")];
  expect(groupByFile(matches).map((file) => [file.path, file.matches.map((found) => found.line)])).toEqual([
    ["a.go", [1, 9]],
    ["pkg/b.go", [2]],
  ]);
  expect(groupByFile([])).toEqual([]);
});

test("shows a line without its indentation, in three parts around the match", () => {
  expect(excerpt(match("a.go", 1, "\t\treturn needle + 1  ", "needle"))).toEqual({
    before: "return ",
    hit: "needle",
    after: " + 1",
  });
});

test("keeps a match that is itself white space", () => {
  expect(excerpt({ path: "a", line: 1, column: 1, text: "    x", matchStart: 0, matchLength: 2 })).toEqual({
    before: "",
    hit: "  ",
    after: "  x",
  });
});

test("says when nothing matched and when the search stopped early", () => {
  expect(searchNote(3, true)).toBeUndefined();
  expect(searchNote(0, true)).toBe("No matches.");
  expect(searchNote(1000, false)).toBe("Showing the first 1,000 matching lines.");
  expect(searchNote(0, false)).toBe("The search took too long. Try a longer text.");
});
