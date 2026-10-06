---
name: project-links
description: Link a page to the current project's card on the Wheelhouse project board, or change, remove or list those links. Use when the user asks to link, attach, add or save a PRD, tech solution, tech design, ticket, pipeline or similar page to the project or its board card, to update or remove such a link, or asks which pages the project links to.
---

# Project links

Each project on the board carries at most one link of each link kind. The links are the chips on
the project's card. `proj` keeps them in the project's file and redraws the board.

Run these from the project's workspace; `proj` then knows which project is meant.

```sh
proj link                      # the link kinds and what the project links to (- = none)
proj link <kind> <url>         # set the project's link of that kind; replaces the old one
proj link rm <kind>            # remove it
```

- `<kind>` is one of the titles `proj link` prints. Case, spaces and punctuation do not matter:
  `"Tech Design"`, `tech-design` and `techdesign` are the same kind. Quote a kind with a space.
- `<url>` is the full address, quoted, starting with `https://`.
- If `proj` answers "not inside a project workspace", name the project before the kind:
  `proj link <project> <kind> <url>`. `proj ls` lists the projects.

## How to use it

1. Run `proj link` first to see the kinds and what is already linked.
2. Pick the kind from what the user said. If the page fits no kind, or two kinds fit, ask the
   user; do not invent a kind, and do not file a page under a kind it is not.
3. If that kind already has a different link, tell the user which address it replaces before you
   set it.
4. Set it, and tell the user in one line what is linked now.

Only run `proj link` when `proj` is installed on the machine you are working on (`command -v
proj`). On a remote host without it, tell the user to add the link from the board: right-click
the project's card, open Links, pick the kind and paste the address.
