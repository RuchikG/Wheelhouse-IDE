/** A line that contains what was searched for, as the host reports it. */
export type SearchMatch = {
  /** Relative to the project's root. */
  path: string;
  /** Both count from 1. */
  line: number;
  column: number;
  /** The line, or the part of a long line around the match. */
  text: string;
  /** Where the match is in `text`. */
  matchStart: number;
  matchLength: number;
};

export type FileMatches = { path: string; matches: SearchMatch[] };

/** The matches by file, in the order they came. */
export function groupByFile(matches: readonly SearchMatch[]): FileMatches[] {
  const files: FileMatches[] = [];
  for (const match of matches) {
    const last = files[files.length - 1];
    if (last?.path === match.path) {
      last.matches.push(match);
    } else {
      files.push({ path: match.path, matches: [match] });
    }
  }
  return files;
}

/** A match's line in three parts, without the indentation in front of it. */
export function excerpt(match: SearchMatch): { before: string; hit: string; after: string } {
  const indent = Math.min(match.text.length - match.text.trimStart().length, match.matchStart);
  const end = match.matchStart + match.matchLength;
  return {
    before: match.text.slice(indent, match.matchStart),
    hit: match.text.slice(match.matchStart, end),
    after: match.text.slice(end).trimEnd(),
  };
}

/** How long a query must be before it is searched for while it is typed. */
export const MINIMUM_TYPED_QUERY = 2;

/** What to say under the results; undefined when nothing needs saying. */
export function searchNote(count: number, isComplete: boolean): string | undefined {
  if (!isComplete) {
    return count === 0
      ? "The search took too long. Try a longer text."
      : `Showing the first ${count.toLocaleString("en-US")} matching lines.`;
  }
  return count === 0 ? "No matches." : undefined;
}
