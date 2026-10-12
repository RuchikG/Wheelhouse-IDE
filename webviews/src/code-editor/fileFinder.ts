/**
 * The files whose path contains every word of `query`, best first: a match in
 * the file's name before one only in its folders, a name that starts with the
 * query before the rest, then shorter paths. Case is ignored.
 */
export function findFiles(paths: readonly string[], query: string, limit: number): string[] {
  const words = query.toLowerCase().split(/\s+/).filter(Boolean);
  if (words.length === 0) {
    return [];
  }
  const ranked: { path: string; rank: number }[] = [];
  for (const path of paths) {
    const lowered = path.toLowerCase();
    if (!words.every((word) => lowered.includes(word))) {
      continue;
    }
    const name = lowered.slice(lowered.lastIndexOf("/") + 1);
    const rank = name.startsWith(words[0]) ? 0 : words.every((word) => name.includes(word)) ? 1 : 2;
    ranked.push({ path, rank });
  }
  ranked.sort((left, right) => left.rank - right.rank || left.path.length - right.path.length);
  return ranked.slice(0, limit).map((entry) => entry.path);
}

/** Why `name` cannot name a file or folder; undefined when it can. */
export function invalidName(name: string): string | undefined {
  if (name === "" || name === "." || name === "..") {
    return "Enter a name.";
  }
  if (name.includes("/")) {
    return "A name cannot contain “/”.";
  }
  return undefined;
}

/** Whether `path` is `folder` or inside it. */
export function isWithin(path: string, folder: string): boolean {
  return path === folder || path.startsWith(`${folder}/`);
}

/** `path` after `from` became `to`; undefined when `path` is not `from` or inside it. */
export function movedPath(path: string, from: string, to: string): string | undefined {
  return isWithin(path, from) ? to + path.slice(from.length) : undefined;
}

/** The folders between `root` and the file at `path`, outermost first; none when the file is not inside `root`. */
export function foldersAbove(path: string, root: string): string[] {
  if (!path.startsWith(`${root}/`)) {
    return [];
  }
  const folders: string[] = [];
  let end = path.indexOf("/", root.length + 1);
  while (end !== -1) {
    folders.push(path.slice(0, end));
    end = path.indexOf("/", end + 1);
  }
  return folders;
}

/**
 * The expanded folders that are gone: their parent folder was listed just now
 * and no longer holds them. A folder under a collapsed or unreadable parent
 * is kept, because nothing was learned about it.
 */
export function vanishedFolders(
  expanded: Iterable<string>,
  listed: ReadonlySet<string>,
  shown: { has(path: string): boolean },
): string[] {
  return [...expanded].filter((folder) => listed.has(folder.slice(0, folder.lastIndexOf("/"))) && !shown.has(folder));
}
