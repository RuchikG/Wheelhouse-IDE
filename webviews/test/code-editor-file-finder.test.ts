import { expect, test } from "bun:test";
import { findFiles, invalidName, movedPath } from "../src/code-editor/fileFinder";

const paths = ["cmd/proj/main.go", "main.go", "docs/main-ideas.md", "internal/mainline/run.go", "README.md"];

test("ranks a name that starts with the query first, then other name matches, then folder matches", () => {
  expect(findFiles(paths, "main", 10)).toEqual([
    "main.go",
    "cmd/proj/main.go",
    "docs/main-ideas.md",
    "internal/mainline/run.go",
  ]);
});

test("every word must match, in any case, and the limit holds", () => {
  expect(findFiles(paths, "PROJ main", 10)).toEqual(["cmd/proj/main.go"]);
  expect(findFiles(paths, "main", 2)).toEqual(["main.go", "cmd/proj/main.go"]);
  expect(findFiles(paths, "   ", 10)).toEqual([]);
  expect(findFiles(paths, "nothing", 10)).toEqual([]);
});

test("names a file or folder cannot have", () => {
  expect(invalidName("")).toBeDefined();
  expect(invalidName("..")).toBeDefined();
  expect(invalidName("a/b.go")).toBeDefined();
  expect(invalidName("b.go")).toBeUndefined();
});

test("a moved folder moves the paths inside it and nothing else", () => {
  expect(movedPath("/p/calc", "/p/calc", "/p/sum")).toBe("/p/sum");
  expect(movedPath("/p/calc/a.go", "/p/calc", "/p/sum")).toBe("/p/sum/a.go");
  expect(movedPath("/p/calculus/a.go", "/p/calc", "/p/sum")).toBeUndefined();
});
