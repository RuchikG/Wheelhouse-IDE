// project-agents: the agents of the selected project, with what each is doing and its
// sub-agents. Wheelhouse IDE shows it in the right sidebar while a project has more than one
// agent, and as a narrow rail when collapsed.

// Wheelhouse IDE installs a second copy with this set, which draws the rail.
const RAIL = false;

const IN_WHEELHOUSE = typeof wheelhouse === "object";
const tone = (light, dark) => (IN_WHEELHOUSE ? light + "|" + dark : dark);

const NEEDS = tone("#B25000", "#FF9F0A");
const NEEDS_FILL = tone("#FF9F0A", "#FF9F0A");
const NEEDS_CARD = tone("#FF9F0A2e", "#FF9F0A1f");
const NEEDS_CARD_HOVER = tone("#FF9F0A47", "#FF9F0A33");
const WORKING = tone("#0A6CDB", "#0A84FF");
const IDLE = tone("#248A3D", "#34C759");
const QUIET = tone("#3c3c4366", "#7f7f7f66");
const CARD = tone("#0000000f", "#7f7f7f14");
const CARD_HOVER = tone("#0000001a", "#7f7f7f33");

const STATE = {
  needs_input: { color: NEEDS_FILL, text: "waiting", rank: 0 },
  working: { color: WORKING, text: "working", rank: 1 },
  idle: { color: IDLE, text: "idle", rank: 2 },
};

const project = computed(() => (data.workspaces() ?? []).find((w) => w.selected));

// Waiting agents lead, then working, then idle; within a state the order does not change.
const agents = computed(() => {
  const w = project();
  return (w?.agents ?? [])
    .filter((a) => STATE[a.status])
    .map((a) => ({ key: a.id, w, a }))
    .sort((x, y) => STATE[x.a.status].rank - STATE[y.a.status].rank || (x.key < y.key ? -1 : 1));
});

// An agent goes by the name of its tab, which `proj` sets from the project file, and its task
// is its session's title or else the last prompt typed in that tab.
const agentTab = (e) => (e.w.tabs ?? []).find((t) => t.id === e.a.panelId);
const agentName = (e) => agentTab(e)?.title || e.a.name || e.a.kind || "agent";
const agentTask = (e) => e.a.title || agentTab(e)?.latestPrompt || "";

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

function jump(e) {
  cmux("workspace.select", { workspace_id: e.w.id });
  if (e.a.surfaceId) cmux("surface.focus", { surface_id: e.a.surfaceId, workspace_id: e.w.id });
}

const setCollapsed = (collapsed) => {
  if (IN_WHEELHOUSE && typeof wheelhouse.agentsPanel === "function") wheelhouse.agentsPanel({ collapsed });
};

// A row that is there only while it has something to show.
const when = (shown, id, row) =>
  ForEach({ items: () => (shown() ? [{ id }] : []), key: (r) => r.id }, row);

const line = (text) => HStack({ spacing: 0 }, [text, Spacer({ minLength: 0 })]);

function childRow(c) {
  return HStack({ spacing: 6 }, [
    Circle({ size: 5 }).fill(() => (c()?.running ? WORKING : QUIET)),
    Text(() => c()?.label || "sub-agent").font(11)
      .color(() => (c()?.running ? "primary" : "secondary")).lineLimit(1).truncation("tail"),
    Spacer({ minLength: 0 }),
    Text(() => (c()?.running ? elapsed(c()?.startedEpoch) : "done"))
      .font(10).monospaced().color("tertiary").layoutPriority(2),
  ]).paddingLeading(13);
}

function agentCard(e) {
  const state = () => STATE[e().a.status] ?? STATE.idle;
  const waiting = () => e().a.status === "needs_input";
  return VStack({ spacing: 4 }, [
    HStack({ spacing: 7 }, [
      Circle({ size: 7 }).fill(() => state().color),
      Text(() => agentName(e())).font(12).weight("semibold").lineLimit(1).truncation("tail"),
      Spacer({ minLength: 0 }),
      Text(() => (state().text + " " + elapsed(e().a.sinceEpoch ?? e().a.lastActivityAt)).trim())
        .font(10).monospaced().color(() => (waiting() ? NEEDS : "tertiary")).layoutPriority(2),
    ]),
    line(Text(() => (e().a.name || e().a.kind || "Agent") + " · " + (e().w.remote?.target || "this Mac"))
      .font(10).color("secondary").lineLimit(1).truncation("tail")),
    when(() => Boolean(agentTask(e())), "task", () =>
      line(Text(() => agentTask(e())).font(11).lineLimit(2).truncation("tail"))),
    ForEach({ items: () => e().a.children ?? [], key: (c) => c.id }, (c) => childRow(c)),
    when(() => Boolean(e().a.directory), "directory", () =>
      line(Text(() => e().a.directory ?? "").font(10).monospaced().color("tertiary")
        .lineLimit(1).truncation("middle"))),
  ])
    .paddingHorizontal(10).paddingVertical(8)
    .cornerRadius(8)
    .background(() => (waiting() ? NEEDS_CARD : CARD))
    .hoverBackground(() => (waiting() ? NEEDS_CARD_HOVER : CARD_HOVER))
    .frame({ maxWidth: "infinity" })
    .help("Go to this agent")
    .onTap(() => jump(e()));
}

function iconButton(icon, help, action) {
  return Image(icon).font(12).color("secondary")
    .paddingHorizontal(5).paddingVertical(4)
    .cornerRadius(6)
    .hoverBackground(CARD_HOVER)
    .help(help)
    .onTap(action);
}

function panel() {
  return VStack({ spacing: 8 }, [
    HStack({ spacing: 6 }, [
      Text("Agents").font(14).weight("semibold"),
      Text(() => (agents().length ? String(agents().length) : "")).font(12).color("secondary"),
      Spacer(),
      ...(IN_WHEELHOUSE ? [iconButton("sidebar.right", "Collapse to a rail", () => setCollapsed(true))] : []),
    ]).paddingHorizontal(4),
    line(Text(() => project()?.title ?? "").font(11).color("secondary").lineLimit(1).truncation("tail"))
      .paddingHorizontal(4),
    ForEach({ items: agents, key: (e) => e.key }, (e) => agentCard(e)),
    when(() => agents().length === 0, "none", () =>
      line(Text("No agents in this project.").font(11).color("tertiary")).paddingHorizontal(4)),
    Spacer(),
  ]).paddingHorizontal(8);
}

function railDot(e) {
  return Circle({ size: 9 }).fill(() => (STATE[e().a.status] ?? STATE.idle).color)
    .padding(6)
    .cornerRadius(6)
    .background(() => (e().a.status === "needs_input" ? NEEDS_CARD : null))
    .hoverBackground(CARD_HOVER)
    .help(() => agentName(e()))
    .onTap(() => jump(e()));
}

function rail() {
  return VStack({ spacing: 4 }, [
    iconButton("sidebar.right", "Show the agents", () => setCollapsed(false)),
    ForEach({ items: agents, key: (e) => e.key }, (e) => railDot(e)),
    Spacer(),
  ]).frame({ maxWidth: "infinity" });
}

sidebar(() => (RAIL ? rail() : panel()), { surface: "glass" })
