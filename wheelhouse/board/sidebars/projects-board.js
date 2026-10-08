// projects-board: every project as a card, grouped by lifecycle lane.
// Lanes are the workspace groups that `proj init` creates; a project is a workspace in one.
//   proj init

// Labels must match the lanes in cmd/proj/manifest.go.
const LANES = ["Design", "Dev", "Review & Test", "Release", "Done"];

// Wheelhouse IDE announces itself to its sidebars and takes a colour as "light|dark", so the
// board has a palette for each appearance there. In cmux it keeps the single one.
const IN_WHEELHOUSE = typeof wheelhouse === "object";
const tone = (light, dark) => (IN_WHEELHOUSE ? light + "|" + dark : dark);

const NEEDS = tone("#B25000", "#FF9F0A");
const NEEDS_FILL = tone("#FF9F0A", "#FF9F0A");
const NEEDS_CARD = tone("#FF9F0A2e", "#FF9F0A1f");
const NEEDS_CARD_HOVER = tone("#FF9F0A47", "#FF9F0A33");
const WORKING = tone("#0A6CDB", "#0A84FF");
const IDLE = tone("#248A3D", "#34C759");
const QUIET = tone("#3c3c4366", "#7f7f7f66");
// An open link's chip: its icon, fill and outline.
const OPEN = tone("#00735F", "#5EE0C2");
const OPEN_FILL = tone("#00A88A2e", "#5EE0C22e");
const OPEN_LINE = tone("#00735F99", "#5EE0C299");
// Cards, chips and buttons sit on the sidebar's glass.
const CARD = tone("#0000000f", "#7f7f7f14");
const CARD_SELECTED = tone("#00000024", "#7f7f7f3d");
const CARD_HOVER = tone("#0000001a", "#7f7f7f33");
const CHIP = tone("#00000014", "#7f7f7f29");
const CHIP_LINE = tone("#00000033", "#7f7f7f4d");
const CHIP_HOVER = tone("#00000029", "#7f7f7f47");
const ROW_HOVER = tone("#00000014", "#7f7f7f24");
// Under a card while it is dragged, so the cards it passes do not show through.
const LIFTED = tone("#E9E9EB", "#2A2A2C");

// `proj` rewrites this line in the installed copy: a sidebar cannot read the project files.
const BOARD = { projects: {}, kinds: [], browserProfile: "", proj: "", home: "" };

const workspaces = () => data.workspaces() ?? [];
const groups = () => data.groups() ?? [];
const laneGroup = (label) => groups().find((g) => g.name === label);
const laneGroups = computed(() => LANES.map(laneGroup).filter(Boolean));

function agentInfo(w) {
  const live = (w?.agents ?? []).filter((a) => a.status !== "ended");
  const needs = live.filter((a) => a.status === "needs_input");
  const working = live.filter((a) => a.status === "working");
  return { total: live.length, needs, working };
}

// Lower sorts first: projects waiting on the user lead their lane.
function rank(w) {
  const a = agentInfo(w);
  if (a.needs.length) return 0;
  if (w.unread > 0) return 1;
  if (a.working.length) return 2;
  return 3;
}

// The last card dropped on the board: until the workspace data has moved on from where the
// card was picked up, the board counts it as already being where the drop sends it.
let dropped = null;
const [dropCount, setDropCount] = signal(0);

const placed = computed(() => {
  dropCount();
  const all = workspaces();
  if (!dropped) return all;
  const at = all.findIndex((w) => w.id === dropped.id);
  if (at !== dropped.at || all[at].group !== dropped.from) {
    dropped = null;
    return all;
  }
  const rest = all.filter((w) => w.id !== dropped.id);
  rest.splice(dropped.place, 0, { ...all[at], group: dropped.group });
  return rest.map((w, index) => ({ ...w, index }));
});

const cardsIn = (label) => () => {
  const g = laneGroup(label);
  if (!g) return [];
  return placed()
    .filter((w) => w.group === g.id && w.id !== g.anchorId)
    .sort((x, y) => rank(x) - rank(y) || x.index - y.index);
};

const others = computed(() => {
  const laneIds = new Set(laneGroups().map((g) => g.id));
  const anchors = new Set(laneGroups().map((g) => g.anchorId));
  return workspaces().filter((w) => !laneIds.has(w.group) && !anchors.has(w.id));
});

function statusColor(w) {
  const a = agentInfo(w);
  if (a.needs.length) return NEEDS_FILL;
  if (a.working.length) return WORKING;
  return a.total ? IDLE : QUIET;
}

function metaLine(w) {
  if (!w) return "";
  const parts = [];
  if (w.branch) parts.push(w.branch + (w.dirty ? "*" : ""));
  if (w.pr) parts.push(w.pr.label || "#" + w.pr.number);
  const a = agentInfo(w);
  if (a.needs.length) parts.push(a.needs.length + " waiting on you");
  else if (a.working.length) parts.push(a.working.length + " working");
  else if (a.total) parts.push(a.total + " idle");
  if (w.progress?.label) parts.push(w.progress.label);
  return parts.join(" · ");
}

function jump(w) {
  cmux("workspace.select", { workspace_id: w.id });
  const waiting = agentInfo(w).needs.find((a) => a.surfaceId);
  if (waiting) cmux("surface.focus", { surface_id: waiting.surfaceId, workspace_id: w.id });
}

// Link chips use sidebar features that older cmux releases lack; there the board goes without.
const HAS_CHIPS = typeof Text("").fixedSize === "function" && typeof Text("").cursor === "function";
// Keeps a short label on one line at its own width where the runtime can.
const snug = (text) => (typeof text.fixedSize === "function" ? text.fixedSize("horizontal") : text);
const KINDS = HAS_CHIPS ? BOARD.kinds ?? [] : [];

const project = (w) => BOARD.projects[w?.title];
const linksOf = (w) => (HAS_CHIPS ? project(w)?.links ?? [] : []);

// A link's tab carries the link's title, which is how the board finds it again.
const linkTab = (w, link) => (w?.tabs ?? []).find((t) => t.title === link?.title);

// Shows the link's tab, opening it first when the project has none: next to the project's
// other link tabs, or in a new browser pane on the right for the first one.
function openLink(w, link) {
  cmux("workspace.select", { workspace_id: w.id });
  const tab = linkTab(w, link);
  if (tab) {
    cmux("surface.focus", { surface_id: tab.surfaceId, workspace_id: w.id });
    return;
  }
  const sibling = linksOf(w).map((other) => linkTab(w, other)).find((t) => t?.surfaceId);
  if (sibling) {
    cmux("surface.focus", { surface_id: sibling.surfaceId, workspace_id: w.id });
    cmux("surface.create", { workspace_id: w.id, type: "browser", url: link.url, focus: "true" });
  } else {
    const params = { workspace_id: w.id, type: "browser", direction: "right", url: link.url, focus: "true" };
    if (BOARD.browserProfile) params.profile = BOARD.browserProfile;
    cmux("pane.create", params);
  }
  // The new tab has the focus, so a rename without a target names it.
  cmux("surface.action", { workspace_id: w.id, action: "rename", title: link.title });
}

// Copies the sign-ins of Chrome or another browser into the profile the link tabs use, with
// the app's own import. Wheelhouse IDE only, like the rest of what is new on the board.
const CAN_IMPORT_SIGN_INS = IN_WHEELHOUSE && HAS_CHIPS;
function importSignIns() {
  const params = { scope: "cookies" };
  if (BOARD.browserProfile) {
    params.to_profile = BOARD.browserProfile;
    params.create_profile = "true";
  }
  cmux("browser.import.dialog", params);
}

function closeLink(w, link) {
  const tab = linkTab(w, link);
  if (tab?.surfaceId) cmux("surface.close", { surface_id: tab.surfaceId, workspace_id: w.id });
}

// The card and the link kind whose address is being typed, if any.
const [editing, setEditing] = signal(null);

function editLink(w, kind) {
  if (!project(w)) {
    log("projects-board: " + w.title + " has no project file to keep links in");
    return;
  }
  setEditing({ workspaceId: w.id, kind: kind.title });
}

const shellQuote = (text) => "'" + String(text).replaceAll("'", "'\\''") + "'";

// A sidebar cannot write the project files, so `proj` does it. Wheelhouse IDE runs it out of
// sight and shows the message when it fails.
const RUNS_PROJ = IN_WHEELHOUSE && typeof wheelhouse.proj === "function" && Boolean(BOARD.home);

// In cmux `proj` gets a workspace of its own, which closes when the command succeeds and
// waits with the message when it fails; the pause keeps a quick success from being taken for
// a crashed command.
function runProj(args, title, failed) {
  if (RUNS_PROJ) {
    wheelhouse.proj(args, { home: BOARD.home, failed });
    return;
  }
  const command = BOARD.proj + " " + args.map(shellQuote).join(" ");
  cmux("workspace.create", {
    title,
    focus: "false",
    initial_command: command + " && sleep 1 || { echo; echo " + shellQuote(failed + " Press Return to close.") + "; read _; }",
  });
}

const saveLinkWith = (args) => runProj(["link", ...args], "Saving link", "The link was not changed.");

// Adding and reopening projects from the board needs Wheelhouse IDE, which announces itself
// to its sidebars; in cmux the board goes without.
const CAN_MANAGE = IN_WHEELHOUSE && Boolean(BOARD.proj);
const newProject = () => wheelhouse.newProject();
const addExample = () => runProj(["example"], "Adding the example", "The example was not added.");
const restoreLanes = () => runProj(["init"], "Restoring lanes", "The lanes were not restored.");
const openProject = (slug) => runProj(["open", slug, "--focus"], "Opening project", "The project was not opened.");
const removeProject = (slug) => runProj(["rm", slug], "Removing project", "The project was not removed.");

function saveLink(w, kind, address) {
  setEditing(null);
  const slug = project(w)?.slug;
  if (!slug || !address.trim()) return;
  // A tab still showing the address that is being replaced would pass for the new link's.
  closeLink(w, { title: kind });
  saveLinkWith([slug, kind, address.trim()]);
}

function removeLink(w, link) {
  const slug = project(w)?.slug;
  if (slug) saveLinkWith(["rm", slug, link.title]);
}

function linkMenu(w) {
  if (!KINDS.length || !BOARD.proj) return [];
  const verb = (kind) => (linksOf(w()).some((l) => l.title === kind.title) ? "Change " : "Add ");
  return [
    Menu("Links", KINDS.map((kind) => Button(() => verb(kind) + kind.title + "…", () => editLink(w(), kind)))),
    Divider(),
  ];
}

function linkChip(w, link) {
  const isOpen = () => Boolean(linkTab(w(), link()));
  return HStack({ spacing: 4 }, [
    Image(() => link()?.icon || "link").font(10)
      .color(() => (isOpen() ? OPEN : "secondary")),
    Text(() => link()?.title ?? "").font(11).lineLimit(1).fixedSize("horizontal"),
  ])
    .paddingHorizontal(6).paddingVertical(3)
    .cornerRadius(6)
    .background(() => (isOpen() ? OPEN_FILL : CHIP))
    .borderColor(() => (isOpen() ? OPEN_LINE : CHIP_LINE)).borderWidth(1)
    .hoverBackground(CHIP_HOVER)
    .help(() => link()?.url ?? "")
    .cursor("pointer")
    .onTap(() => openLink(w(), link()))
    .contextMenu([
      Button(() => (isOpen() ? "Show tab" : "Open tab"), () => openLink(w(), link())),
      Button("Close tab", () => closeLink(w(), link())),
      Button("Open in default browser", () => openURL(link().url)),
      ...(CAN_IMPORT_SIGN_INS ? [Button("Import sign-ins from a browser…", importSignIns)] : []),
      ...(BOARD.proj
        ? [
            Divider(),
            Button("Change link…", () => editLink(w(), link())),
            Button("Remove link", () => removeLink(w(), link())),
          ]
        : []),
    ]);
}

// One named chip to a row, on every card.
function linkChips(w) {
  return ForEach({ items: () => linksOf(w()), key: (link) => link.title + "\n" + link.url }, (link) =>
    HStack({ spacing: 0 }, [linkChip(w, link), Spacer({ minLength: 0 })]));
}

function linkEditor(w) {
  const rows = () => {
    const e = editing();
    return e && e.workspaceId === w()?.id ? [e] : [];
  };
  return ForEach({ items: rows, key: (e) => e.workspaceId + "\n" + e.kind }, (e) =>
    HStack({ spacing: 5 }, [
      Image(() => KINDS.find((k) => k.title === e()?.kind)?.icon || "link").font(10).color("secondary"),
      TextField("", {
        placeholder: () => "Paste the " + (e()?.kind ?? "") + " link, then Return",
        onSubmit: (text) => saveLink(w(), e().kind, text),
        onCancel: () => setEditing(null),
      }),
    ]));
}

// The lane names `proj` writes into a project file, by label.
const LANE_KEYS = { "Design": "design", "Dev": "dev", "Review & Test": "review", "Release": "release", "Done": "done" };

function moveTo(w, label) {
  const g = laneGroup(label);
  if (!g) {
    log("projects-board: lane " + label + " is missing; run `proj init`");
    return;
  }
  cmux("workspace.group.add", { group_id: g.id, workspace_id: w.id });
  // The project file keeps the lane too, so that a project closed and opened again comes
  // back where it was left.
  const slug = project(w)?.slug;
  if (CAN_MANAGE && slug) runProj(["lane", slug, LANE_KEYS[label]], "Moving project", "The project file still names the old lane.");
}

function laneMenu(w, title) {
  return Menu(title, LANES.map((label) => Button(label, () => moveTo(w(), label))));
}

function badge(text, color) {
  return Text(text)
    .font(9).weight("semibold").color("white")
    .paddingHorizontal(() => (text() ? 5 : 0))
    .paddingVertical(() => (text() ? 1 : 0))
    .background(() => (text() ? color : null))
    .cornerRadius(6);
}

// A row that is there only while it has something to show, so a card is as tall as its content.
const when = (shown, id, row) =>
  ForEach({ items: () => (shown() ? [{ id }] : []), key: (r) => r.id }, row);

function card(w) {
  const hot = () => agentInfo(w()).needs.length > 0;
  return VStack({ spacing: 3 }, [
    HStack({ spacing: 6 }, [
      Circle({ size: 7 }).fill(() => statusColor(w())),
      Text(() => w()?.title ?? "")
        .font(12).weight("semibold").lineLimit(1).truncation("tail"),
      Spacer({ minLength: 0 }),
      badge(() => (w()?.remote?.target ? "remote" : ""), "#5E5CE6").layoutPriority(2),
      badge(() => (w()?.unread > 0 ? String(w().unread) : ""), "#E4573D").layoutPriority(2),
    ]),
    when(() => Boolean(w()?.description), "summary", () =>
      HStack({ spacing: 0 }, [
        Text(() => w()?.description ?? "")
          .font(11).color("secondary").lineLimit(2).truncation("tail"),
        Spacer({ minLength: 0 }),
      ])),
    when(() => Boolean(metaLine(w())), "meta", () =>
      HStack({ spacing: 0 }, [
        Text(() => metaLine(w()))
          .font(10).monospaced().color("tertiary").lineLimit(1).truncation("middle"),
        Spacer({ minLength: 0 }),
      ])),
    when(() => Boolean(w()?.progress), "progress", () =>
      ProgressView({ value: () => w()?.progress?.value ?? 0 }).frame({ height: 4 })),
    linkChips(w),
    linkEditor(w),
  ])
    .paddingHorizontal(10).paddingVertical(7)
    .cornerRadius(8)
    .background(() => (hot() ? NEEDS_CARD : w()?.selected ? CARD_SELECTED : CARD))
    .hoverBackground(() => (hot() ? NEEDS_CARD_HOVER : CARD_HOVER))
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w()))
    .contextMenu([
      ...linkMenu(w),
      laneMenu(w, "Move to lane"),
      Button("Take off the board", () => cmux("workspace.group.remove", { workspace_id: w().id })),
      Divider(),
      Button(() => (w()?.unread > 0 ? "Mark as read" : "Mark as unread"), () =>
        cmux("workspace.action", { action: w()?.unread > 0 ? "mark_read" : "mark_unread", workspace_id: w().id })),
    ]);
}

function lane(label) {
  const items = cardsIn(label);
  return VStack({ spacing: 4 }, [
    HStack({ spacing: 6 }, [
      Text(label.toUpperCase()).font(10).weight("semibold")
        .color(() => (laneGroup(label) ? "secondary" : "tertiary")),
      Spacer(),
      Text(() => (items().length ? String(items().length) : "")).font(10).monospaced().color("tertiary"),
    ]).paddingHorizontal(4),
    ForEach({ items, key: (w) => w.id }, (w) => card(w)),
    Text(() => (items().length ? "" : laneGroup(label) ? "—" : CAN_MANAGE ? "missing · click to restore" : "not created · run proj init"))
      .font(10).color("tertiary").paddingHorizontal(4)
      .onTap(() => {
        if (CAN_MANAGE && !laneGroup(label)) restoreLanes();
      }),
  ]);
}

// In Wheelhouse IDE a card can be dragged to another lane, or to another place in its own.
// For that the lanes are one list of lane names, cards and the mark of an empty lane.
const CAN_DRAG = IN_WHEELHOUSE && typeof Reorderable === "function";

const laneRows = computed(() => {
  const rows = [];
  for (const label of LANES) {
    const cards = cardsIn(label)();
    rows.push({ id: "lane:" + label, kind: "lane", label, count: cards.length });
    for (const w of cards) rows.push({ id: w.id, kind: "card", label });
    if (!cards.length) rows.push({ id: "empty:" + label, kind: "empty", label });
  }
  // The list keeps a dropped card where it was let go until its rows change, and a drop may
  // change nothing: a card cannot be put above one that is waiting on you. This row changes
  // with every drop.
  rows.push({ id: "drop:" + dropCount(), kind: "end", label: "" });
  return rows;
});

// The lane a card lands in when it is dropped at `index` of the list: the lane of the row
// above it.
const rowsWithout = (id) => laneRows().filter((row) => row.id !== id && row.kind !== "end");
const laneAt = (rows, index) => rows[Math.min(index, rows.length) - 1]?.label ?? LANES[0];

// The lane the card being dragged would land in, while it is another than its own.
const [dragLane, setDragLane] = signal(null);

function dragChanged(state) {
  const from = state && laneRows().find((row) => row.id === state.id)?.label;
  const to = state ? laneAt(rowsWithout(state.id), state.index) : null;
  setDragLane(to && to !== from ? to : null);
}

function dropCard(id, index) {
  const all = workspaces();
  const at = all.findIndex((w) => w.id === id);
  const rows = rowsWithout(id);
  const label = laneAt(rows, index);
  const g = laneGroup(label);
  dropped = null;
  if (at < 0 || !g) {
    setDropCount(dropCount() + 1);
    return;
  }
  const w = all[at];
  const rest = all.filter((x) => x.id !== id);
  // A lane lists the cards that wait on you first, so the place asked for is one among the
  // cards that sort like this one: before the next of them below the drop, else after the
  // last of them above it, else at the end of the lane.
  const peer = (row) => {
    const other = row?.kind === "card" && row.label === label ? rest.find((x) => x.id === row.id) : null;
    return other && rank(other) === rank(w) ? other : null;
  };
  const below = rows.slice(index).map(peer).find(Boolean);
  const above = rows.slice(0, index).reverse().map(peer).find(Boolean);
  const place = below
    ? rest.indexOf(below)
    : above
      ? rest.indexOf(above) + 1
      : w.group === g.id
        ? at
        : rest.map((x) => x.group).lastIndexOf(g.id) + 1;
  if (w.group !== g.id || place !== at) dropped = { id, at, from: w.group, group: g.id, place };
  setDropCount(dropCount() + 1);
  if (w.group !== g.id) moveTo(w, label);
  if (w.group !== g.id || place !== at) cmux("workspace.reorder", { workspace_id: id, index: place });
}

function laneRow(row, first) {
  const label = row().label;
  if (row().kind === "lane") {
    return HStack({ spacing: 6 }, [
      Text(label.toUpperCase()).font(10).weight("semibold")
        .color(() => (dragLane() === label ? OPEN : laneGroup(label) ? "secondary" : "tertiary")),
      Spacer(),
      Text(() => (row()?.count ? String(row().count) : "")).font(10).monospaced().color("tertiary"),
    ]).paddingHorizontal(4).paddingTop(first ? 0 : 8).fixed();
  }
  if (row().kind === "end") return Text("").fixed();
  if (row().kind === "empty") {
    return Text(() => (laneGroup(label) ? "—" : CAN_MANAGE ? "missing · click to restore" : "not created · run proj init"))
      .font(10).color("tertiary").paddingHorizontal(4)
      .onTap(() => {
        if (CAN_MANAGE && !laneGroup(label)) restoreLanes();
      })
      .fixed();
  }
  // A card keeps showing its workspace for the moment between its closing and its row going.
  let last;
  const id = row().id;
  const w = () => (last = workspaces().find((x) => x.id === id) ?? last);
  return card(w).dragBackground(LIFTED);
}

function lanes() {
  if (!CAN_DRAG) return LANES.map(lane);
  return [
    Reorderable(
      { items: laneRows, key: (row) => row.id, spacing: 4, onMove: dropCard, onDragChange: dragChanged },
      (row) => laneRow(row, row().id === "lane:" + LANES[0])),
  ];
}

function otherRow(w) {
  return HStack({ spacing: 6 }, [
    Circle({ size: 6 }).fill(() => statusColor(w())),
    Text(() => w()?.title ?? "").font(11).color("secondary").lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
  ])
    .paddingHorizontal(10).paddingVertical(4)
    .cornerRadius(6)
    .background(() => (w()?.selected ? CARD_SELECTED : null))
    .hoverBackground(ROW_HOVER)
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w()))
    .contextMenu([laneMenu(w, "Add to lane")]);
}

function textButton(label, action) {
  return Text(label).font(11).weight("medium")
    .paddingHorizontal(8).paddingVertical(4)
    .cornerRadius(6)
    .background(CHIP)
    .hoverBackground(CHIP_HOVER)
    .onTap(action);
}

// Shown while no lane has a card: what the board is for and the ways to fill it.
const boardIsEmpty = computed(() =>
  laneGroups().length > 0 && LANES.every((label) => cardsIn(label)().length === 0));

function emptyBoard() {
  if (!CAN_MANAGE) return [];
  const actions = [textButton("New Project…", newProject)];
  if (!BOARD.projects["Example Project"]) actions.push(textButton("Add the example", addExample));
  return [
    ForEach({ items: () => (boardIsEmpty() ? [{ id: "empty" }] : []), key: (row) => row.id }, () =>
      VStack({ spacing: 6 }, [
        HStack({ spacing: 0 }, [Text("No projects open").font(12).weight("semibold"), Spacer({ minLength: 0 })]),
        HStack({ spacing: 0 }, [
          Text("A project is a workspace with its folder, its links and its agents.")
            .font(11).color("secondary").lineLimit(3),
          Spacer({ minLength: 0 }),
        ]),
        HStack({ spacing: 6 }, [...actions, Spacer({ minLength: 0 })]),
      ])
        .paddingHorizontal(10).paddingVertical(8)
        .cornerRadius(8)
        .background(CARD)
        .frame({ maxWidth: "infinity" })),
  ];
}

// Projects whose workspace was closed: a click opens them again, and the menu takes one off
// the board for good.
const closedProjects = computed(() => {
  const open = new Set(workspaces().map((w) => w.title));
  return Object.keys(BOARD.projects).filter((name) => !open.has(name)).sort()
    .map((name) => ({ name, slug: BOARD.projects[name].slug }));
});

function closedRow(p) {
  return HStack({ spacing: 6 }, [
    Image("arrow.up.forward.square").font(10).color("tertiary"),
    Text(() => p()?.name ?? "").font(11).color("secondary").lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
  ])
    .paddingHorizontal(10).paddingVertical(4)
    .cornerRadius(6)
    .hoverBackground(ROW_HOVER)
    .frame({ maxWidth: "infinity" })
    .help("Open this project")
    .onTap(() => openProject(p().slug))
    .contextMenu([
      Button("Open", () => openProject(p().slug)),
      Divider(),
      Button("Remove from board", () => removeProject(p().slug)),
    ]);
}

function closedSection() {
  if (!CAN_MANAGE) return [];
  return [
    VStack({ spacing: 2 }, [
      Text(() => (closedProjects().length ? "CLOSED" : ""))
        .font(10).weight("semibold").color("tertiary").paddingHorizontal(4),
      ForEach({ items: closedProjects, key: (p) => p.slug }, (p) => closedRow(p)),
    ]),
  ];
}

// The sidebar shows the board, or every agent on it by what it is doing.
const [view, setView] = signal("projects");

const STATES = [
  { status: "needs_input", label: "NEEDS YOU", color: NEEDS_FILL, text: NEEDS, strong: true },
  { status: "working", label: "WORKING", color: WORKING, text: "tertiary", strong: false },
  { status: "idle", label: "IDLE", color: IDLE, text: "tertiary", strong: false },
];

const liveAgents = computed(() => {
  const anchors = new Set(laneGroups().map((g) => g.anchorId));
  const out = [];
  for (const w of workspaces()) {
    if (anchors.has(w.id)) continue;
    for (const a of w.agents ?? []) {
      if (a.status !== "ended") out.push({ key: w.id + ":" + a.id, w, a });
    }
  }
  return out;
});

const waitingAgents = computed(() => liveAgents().filter((e) => e.a.status === "needs_input").length);

// The longest wait leads; the other states keep the order of the board.
const agentsIn = (status) => () =>
  liveAgents()
    .filter((e) => e.a.status === status)
    .sort((x, y) =>
      (status === "needs_input" ? (x.a.sinceEpoch ?? 0) - (y.a.sinceEpoch ?? 0) : 0)
      || x.w.index - y.w.index || (x.key < y.key ? -1 : 1));

// An agent goes by the name of its tab, which `proj` sets from the project file, and its task
// is its session's title or else the last prompt typed in that tab.
const agentTab = (e) => (e.w.tabs ?? []).find((t) => t.id === e.a.panelId);
const agentName = (e) => agentTab(e)?.title || e.a.name || e.a.kind || "agent";

function agentTask(e) {
  const running = (e.a.children ?? []).filter((c) => c.running).length;
  const parts = [];
  const task = e.a.title || agentTab(e)?.latestPrompt;
  if (task) parts.push(task);
  if (running) parts.push(running + (running === 1 ? " sub-agent" : " sub-agents"));
  return parts.join(" · ");
}

function elapsed(since) {
  const now = data.clock()?.epoch ?? 0;
  if (!since || !now) return "";
  const s = Math.max(0, Math.floor(now - since));
  if (s < 60) return s + "s";
  const m = Math.floor(s / 60);
  if (m < 60) return m + "m";
  const h = Math.floor(m / 60);
  return h < 24 ? h + "h" : Math.floor(h / 24) + "d";
}

function jumpToAgent(e) {
  cmux("workspace.select", { workspace_id: e.w.id });
  if (e.a.surfaceId) cmux("surface.focus", { surface_id: e.a.surfaceId, workspace_id: e.w.id });
}

function agentRow(e, state) {
  return HStack({ spacing: 8 }, [
    Circle({ size: 7 }).fill(state.color),
    VStack({ spacing: 1 }, [
      HStack({ spacing: 4 }, [
        Text(() => agentName(e())).font(12).weight("semibold").lineLimit(1).truncation("tail"),
        Text(() => "· " + (e().w.title ?? "")).font(11).color("secondary").lineLimit(1).truncation("tail"),
        Spacer({ minLength: 0 }),
      ]),
      when(() => Boolean(agentTask(e())), "task", () =>
        HStack({ spacing: 0 }, [
          Text(() => agentTask(e())).font(11).color("secondary").lineLimit(1).truncation("tail"),
          Spacer({ minLength: 0 }),
        ])),
    ]),
    badge(() => (e().w.remote?.target ? "remote" : ""), "#5E5CE6").layoutPriority(2),
    Text(() => elapsed(e().a.sinceEpoch ?? e().a.lastActivityAt))
      .font(10).monospaced().color("tertiary").layoutPriority(2),
  ])
    .paddingHorizontal(10).paddingVertical(6)
    .cornerRadius(8)
    .background(state.strong ? NEEDS_CARD : CARD)
    .hoverBackground(state.strong ? NEEDS_CARD_HOVER : CARD_HOVER)
    .frame({ maxWidth: "infinity" })
    .onTap(() => jumpToAgent(e()));
}

function stateSection(state) {
  const items = agentsIn(state.status);
  return VStack({ spacing: 4 }, [
    HStack({ spacing: 6 }, [
      Text(state.label).font(10).weight("semibold")
        .color(() => (items().length ? state.text : "tertiary")),
      Spacer(),
      Text(() => (items().length ? String(items().length) : "—"))
        .font(10).monospaced().color("tertiary"),
    ]).paddingHorizontal(4),
    ForEach({ items, key: (e) => e.key }, (e) => agentRow(e, state)),
  ]);
}

function viewTab(id, label) {
  return HStack({ spacing: 4 }, label)
    .paddingHorizontal(8).paddingVertical(3)
    .cornerRadius(6)
    .background(() => (view() === id ? CARD_SELECTED : null))
    .hoverBackground(CARD_HOVER)
    .onTap(() => setView(id));
}

function headerButton(icon, help, action) {
  return Image(icon).font(12).color("secondary")
    .paddingHorizontal(5).paddingVertical(4)
    .cornerRadius(6)
    .hoverBackground(CARD_HOVER)
    .help(help)
    .onTap(action);
}

function headerButtons() {
  return [
    ...(CAN_IMPORT_SIGN_INS
      ? [headerButton("person.badge.key", "Import sign-ins from Chrome or another browser", importSignIns)]
      : []),
    ...(CAN_MANAGE ? [headerButton("plus", "New project", newProject)] : []),
  ];
}

sidebar(() =>
  VStack({ spacing: 12 }, [
    HStack({ spacing: 2 }, [
      viewTab("projects", [snug(Text("Projects").font(13).weight("semibold").lineLimit(1))]),
      viewTab("agents", [
        snug(Text("Agents").font(13).weight("semibold").lineLimit(1)),
        snug(Text(() => (waitingAgents() ? String(waitingAgents()) : "")).font(9).weight("bold").color("#1C1C1E").lineLimit(1))
          .paddingHorizontal(() => (waitingAgents() ? 5 : 0))
          .paddingVertical(() => (waitingAgents() ? 1 : 0))
          .background(() => (waitingAgents() ? NEEDS_FILL : null))
          .cornerRadius(6),
      ]),
      Spacer(),
      ...headerButtons(),
    ]),
    when(() => view() === "projects", "projects", () =>
      VStack({ spacing: 12 }, [
        ...emptyBoard(),
        ...lanes(),
        ...closedSection(),
        VStack({ spacing: 2 }, [
          Text(() => (others().length ? "NOT ON THE BOARD" : ""))
            .font(10).weight("semibold").color("tertiary").paddingHorizontal(4),
          ForEach({ items: others, key: (w) => w.id }, (w) => otherRow(w)),
        ]),
      ])),
    when(() => view() === "agents", "agents", () =>
      VStack({ spacing: 12 }, STATES.map(stateSection))),
    Spacer(),
  ]).paddingHorizontal(8).paddingVertical(8),
  { surface: "glass" }
)
