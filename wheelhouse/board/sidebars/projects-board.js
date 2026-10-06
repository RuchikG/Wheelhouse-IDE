// projects-board: every project as a card, grouped by lifecycle lane.
// Lanes are the workspace groups that `proj init` creates; a project is a workspace in one.
//   proj init && cmux sidebar open projects-board

// Labels must match the lanes in cmd/proj/manifest.go.
const LANES = ["Design", "Dev", "Review & Test", "Release", "Done"];

const NEEDS = "#FF9F0A";
const WORKING = "#0A84FF";
const IDLE = "#34C759";
const QUIET = "#7f7f7f66";
const OPEN = "#5EE0C2";

// `proj` rewrites this line in the installed copy: a sidebar cannot read the project files.
const BOARD = { projects: {}, browserProfile: "" };

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

const cardsIn = (label) => () => {
  const g = laneGroup(label);
  if (!g) return [];
  return workspaces()
    .filter((w) => w.group === g.id && w.id !== g.anchorId)
    .sort((x, y) => rank(x) - rank(y) || x.index - y.index);
};

const others = computed(() => {
  const laneIds = new Set(laneGroups().map((g) => g.id));
  const anchors = new Set(laneGroups().map((g) => g.anchorId));
  return workspaces().filter((w) => !laneIds.has(w.group) && !anchors.has(w.id));
});

const needsYou = computed(() => {
  const anchors = new Set(laneGroups().map((g) => g.anchorId));
  return workspaces().filter((w) => !anchors.has(w.id) && agentInfo(w).needs.length > 0).length;
});

function statusColor(w) {
  const a = agentInfo(w);
  if (a.needs.length) return NEEDS;
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

const linksOf = (w) => (HAS_CHIPS ? BOARD.projects[w?.title]?.links ?? [] : []);

// A link's tab carries the link's title, which is how the board finds it again.
const linkTab = (w, link) => (w?.tabs ?? []).find((t) => t.title === link?.title);

// The selected card names its links, one to a row; the other cards show one row of icons.
function linkRows(w) {
  const links = linksOf(w);
  if (!links.length) return [];
  if (!w.selected) return [{ key: "icons", labelled: false, links }];
  return links.map((link, i) => ({ key: "labelled-" + i, labelled: true, links: [link] }));
}

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

function closeLink(w, link) {
  const tab = linkTab(w, link);
  if (tab?.surfaceId) cmux("surface.close", { surface_id: tab.surfaceId, workspace_id: w.id });
}

function linkChip(w, row, link) {
  const isOpen = () => Boolean(linkTab(w(), link()));
  return HStack({ spacing: 4 }, [
    Image(() => link()?.icon || "link").font(10)
      .color(() => (isOpen() ? OPEN : "secondary")),
    Text(() => (row()?.labelled ? link()?.title ?? "" : ""))
      .font(11).lineLimit(1).fixedSize("horizontal"),
  ])
    .paddingHorizontal(6).paddingVertical(3)
    .cornerRadius(6)
    .background(() => (isOpen() ? OPEN + "2e" : "#7f7f7f29"))
    .borderColor(() => (isOpen() ? OPEN + "99" : "#7f7f7f4d")).borderWidth(1)
    .hoverBackground("#7f7f7f47")
    .help(() => link()?.title ?? "")
    .cursor("pointer")
    .onTap(() => openLink(w(), link()))
    .contextMenu([
      Button(() => (isOpen() ? "Show tab" : "Open tab"), () => openLink(w(), link())),
      Button("Close tab", () => closeLink(w(), link())),
      Divider(),
      Button("Open in default browser", () => openURL(link().url)),
    ]);
}

function linkChips(w) {
  return ForEach({ items: () => linkRows(w()), key: (row) => row.key }, (row) =>
    HStack({ spacing: 5 }, [
      ForEach({ items: () => row()?.links ?? [], key: (link) => link.title + "\n" + link.url }, (link) =>
        linkChip(w, row, link)),
      Spacer({ minLength: 0 }),
    ]));
}

function moveTo(w, label) {
  const g = laneGroup(label);
  if (!g) {
    log("projects-board: lane " + label + " is missing; run `proj init`");
    return;
  }
  cmux("workspace.group.add", { group_id: g.id, workspace_id: w.id });
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
    HStack({ spacing: 0 }, [
      Text(() => w()?.description ?? "")
        .font(11).color("secondary").lineLimit(2).truncation("tail"),
      Spacer({ minLength: 0 }),
    ]),
    HStack({ spacing: 0 }, [
      Text(() => metaLine(w()))
        .font(10).monospaced().color("tertiary").lineLimit(1).truncation("middle"),
      Spacer({ minLength: 0 }),
    ]),
    ProgressView({ value: () => w()?.progress?.value ?? 0 })
      .opacity(() => (w()?.progress ? 1 : 0))
      .frame(() => ({ height: w()?.progress ? 4 : 0 })),
    linkChips(w),
  ])
    .paddingHorizontal(10).paddingVertical(7)
    .cornerRadius(8)
    .background(() => (hot() ? "#FF9F0A1f" : w()?.selected ? "#7f7f7f3d" : "#7f7f7f14"))
    .hoverBackground(() => (hot() ? "#FF9F0A33" : "#7f7f7f33"))
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w()))
    .contextMenu([
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
    Text(() => (items().length ? "" : laneGroup(label) ? "—" : "not created · run proj init"))
      .font(10).color("tertiary").paddingHorizontal(4),
  ]);
}

function otherRow(w) {
  return HStack({ spacing: 6 }, [
    Circle({ size: 6 }).fill(() => statusColor(w())),
    Text(() => w()?.title ?? "").font(11).color("secondary").lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
  ])
    .paddingHorizontal(10).paddingVertical(4)
    .cornerRadius(6)
    .background(() => (w()?.selected ? "#7f7f7f3d" : null))
    .hoverBackground("#7f7f7f24")
    .frame({ maxWidth: "infinity" })
    .onTap(() => jump(w()))
    .contextMenu([laneMenu(w, "Add to lane")]);
}

sidebar(() =>
  VStack({ spacing: 12 }, [
    HStack({ spacing: 6 }, [
      Text("Projects").font(14).weight("semibold"),
      Spacer(),
      Text(() => (needsYou() ? needsYou() + " waiting on you" : ""))
        .font(10).weight("semibold").color(NEEDS),
    ]).paddingHorizontal(4),
    ...LANES.map(lane),
    VStack({ spacing: 2 }, [
      Text(() => (others().length ? "NOT ON THE BOARD" : ""))
        .font(10).weight("semibold").color("tertiary").paddingHorizontal(4),
      ForEach({ items: others, key: (w) => w.id }, (w) => otherRow(w)),
    ]),
    Spacer(),
  ]).paddingHorizontal(8).paddingVertical(8),
  { surface: "glass" }
)
