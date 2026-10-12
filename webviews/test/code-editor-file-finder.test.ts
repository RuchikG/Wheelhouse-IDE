import { expect, test } from "bun:test";
import { findFiles, foldersAbove, invalidName, movedPath, vanishedFolders } from "../src/code-editor/fileFinder";

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

test("the folders above a file are listed from the root down", () => {
  expect(foldersAbove("/p/internal/cart/cart.go", "/p")).toEqual(["/p/internal", "/p/internal/cart"]);
  expect(foldersAbove("/p/main.go", "/p")).toEqual([]);
});

test("a file outside the root has no folders to show", () => {
  expect(foldersAbove("/elsewhere/mod/a.go", "/p")).toEqual([]);
  expect(foldersAbove("/project/a/b.go", "/p")).toEqual([]);
});

test("an expanded folder is forgotten only when its listed parent no longer holds it", () => {
  const expanded = ["/p/a", "/p/gone", "/p/a/deep", "/p/closed/inner", "/p/offline/x"];
  const listed = new Set(["/p", "/p/a"]);
  const shown = new Set(["/p/a", "/p/a/deep", "/p/closed", "/p/offline"]);
  expect(vanishedFolders(expanded, listed, shown)).toEqual(["/p/gone"]);
});

test("nothing is forgotten when the root could not be listed", () => {
  expect(vanishedFolders(["/p/a", "/p/a/b"], new Set(), new Set())).toEqual([]);
});
