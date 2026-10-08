// project-agents: the agents of the selected project, with what each is doing and its
// sub-agents, and under them the project's earlier sessions, each with a way back into it.
// Wheelhouse IDE shows it in the right sidebar while a project is selected; collapsed, it
// leaves an Agents button in the title bar.

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

// Earlier sessions come from Wheelhouse IDE, the latest first; cmux itself lists none.
const sessions = computed(() => project()?.sessions ?? []);
const CAN_OPEN_SESSIONS = IN_WHEELHOUSE && typeof wheelhouse.session === "function";

const DAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"];
const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"];
const two = (n) => (n < 10 ? "0" + n : String(n));
const dayNumber = (d) => Math.floor((d.getTime() - d.getTimezoneOffset() * 60000) / 86400000);

// "Today 14:05", "Yesterday 17:31", "Mon 5 Oct 15:48".
function startedAt(epoch) {
  if (!epoch) return "";
  const d = new Date(epoch * 1000);
  const time = two(d.getHours()) + ":" + two(d.getMinutes());
  const now = data.clock()?.epoch;
  const ago = now ? dayNumber(new Date(now * 1000)) - dayNumber(d) : -1;
  if (ago === 0) return "Today " + time;
  if (ago === 1) return "Yesterday " + time;
  return DAYS[d.getDay()] + " " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + time;
}

function lasted(s) {
  if (!s.startedEpoch || !s.endedEpoch) return "";
  const m = Math.floor(Math.max(0, s.endedEpoch - s.startedEpoch) / 60);
  if (m < 1) return "under a minute";
  if (m < 60) return m + " min";
  return Math.floor(m / 60) + " h" + (m % 60 ? " " + (m % 60) + " min" : "");
}

const sessionMeta = (s) =>
  [startedAt(s.startedEpoch), lasted(s), s.host || "this Mac"].filter(Boolean).join(" · ");

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

function sessionRow(s) {
  const resumable = () => CAN_OPEN_SESSIONS && Boolean(s()?.canResume);
  return VStack({ spacing: 4 }, [
    HStack({ spacing: 6 }, [
      Text(() => s()?.name || s()?.kind || "Agent").font(10).weight("semibold").color("secondary")
        .lineLimit(1)
        .paddingHorizontal(5).paddingVertical(1)
        .background(CARD_HOVER).cornerRadius(4),
      Spacer({ minLength: 0 }),
      when(resumable, "resume", () =>
        Text("Resume").font(11).weight("semibold").color(WORKING).lineLimit(1)
          .paddingHorizontal(8).paddingVertical(3)
          .cornerRadius(6)
          .background(CARD)
          .hoverBackground(CARD_HOVER)
          .help("Open this session again in a new tab")
          .onTap(() => wheelhouse.session(s()))),
      when(() => CAN_OPEN_SESSIONS, "link", () =>
        iconButton("link", "Copy this session's link", () => wheelhouse.session(s(), { copyLink: true }))),
    ]),
    line(Text(() => s()?.title || "No prompt recorded").font(11)
      .color(() => (s()?.title ? "primary" : "tertiary")).lineLimit(2).truncation("tail")),
    line(Text(() => sessionMeta(s() ?? {})).font(10).color("tertiary").lineLimit(1).truncation("tail")),
  ])
    .paddingHorizontal(10).paddingVertical(7)
    .cornerRadius(8)
    .background(CARD)
    .frame({ maxWidth: "infinity" });
}

function earlierSessions() {
  return [
    HStack({ spacing: 6 }, [
      Text("Earlier sessions").font(14).weight("semibold"),
      Text(() => (sessions().length ? String(sessions().length) : "")).font(12).color("secondary"),
      Spacer(),
    ]).paddingHorizontal(4).paddingTop(10),
    ForEach({ items: sessions, key: (s) => s.id }, (s) => sessionRow(s)),
    when(() => sessions().length === 0, "none", () =>
      line(Text("Sessions that end in this project are listed here.").font(11).color("tertiary"))
        .paddingHorizontal(4)),
  ];
}

function panel() {
  return VStack({ spacing: 8 }, [
    HStack({ spacing: 6 }, [
      Text("Agents").font(14).weight("semibold"),
      Text(() => (agents().length ? String(agents().length) : "")).font(12).color("secondary"),
      Spacer(),
      ...(IN_WHEELHOUSE ? [iconButton("sidebar.right", "Collapse to the Agents button", () => setCollapsed(true))] : []),
    ]).paddingHorizontal(4),
    line(Text(() => project()?.title ?? "").font(11).color("secondary").lineLimit(1).truncation("tail"))
      .paddingHorizontal(4),
    ForEach({ items: agents, key: (e) => e.key }, (e) => agentCard(e)),
    when(() => agents().length === 0, "none", () =>
      line(Text("No agent is running in this project.").font(11).color("tertiary")).paddingHorizontal(4)),
    ...(IN_WHEELHOUSE ? earlierSessions() : []),
    Spacer(),
  ]).paddingHorizontal(8).paddingVertical(8);
}

sidebar(() => panel(), { surface: "glass" })
