# agent-notify2 — design lock

A ground-up rebuild of `ai/agent-notify`, developed alongside the original and
promoted over it when finished. This file is the contract: the principles we are
building to, the measurements those principles were tested against, the decisions
already taken, and — just as importantly — the options we considered and rejected,
so none of them get re-litigated by accident three steps from now.

Status markers used throughout:

- **LOCKED** — decided. Do not reopen without new evidence.
- **PROPOSED** — recommended from measured data, awaiting explicit sign-off.
- **OPEN** — genuinely undecided.

---

## 1. Principles

**P1. Everything lives in the module.** All logic, all graphics, for every tool —
zellij, SketchyBar, Claude Code, and any client added later. Nothing of substance
may live in `~/.config/sketchybar/plugins/*.sh`, in `sketchybarrc`, or in a shell
glue script. The bar's config gets exactly one line: a call into the module.

**P2. All logic is written in nushell.** No bash, no other language, anywhere in
the module. This is a hard constraint and it was tested before being accepted —
see §2.

**P3. It must be efficient and fast to load.** Performance is a first-class
concern, discussed explicitly and measured rather than assumed. Every decision in
§4 that trades one cost against another cites a number from §3.

**P4. The on-disk store is the core.** Everything else is a projection of it. The
store must offer (a) powerful and precise ways to write it, and (b) submodules
that integrate clients onto it — zellij, SketchyBar, and others — as **opt-in**
integrations.

**P5. Agent-agnostic.** This is not a Claude Code tool. *Every* agent must be able
to call the entry points — another CLI agent, a script, a cron job, something not
yet written. Claude is one client among N, and its payload adapter is a
convenience, not the path. Three things follow, and they are design constraints
rather than aspirations:

- **The write API is a public interface, not an admin convenience.** A foreign
  agent talks to us by running a command, so the store's command surface needs
  typed flags *and* a JSON body on stdin — the lingua franca for an agent written
  in bash or python — with clear errors and machine-readable output.
- **Identifiers are opaque.** The core may not assume a UUID or any other shape.
- **The state vocabulary is the one thing the core must close** (§4.1). Everything
  else opens up; states cannot, because surfaces render them. A shared vocabulary
  is what an adapter adapts *to* — it is the mechanism that makes P5 work, not a
  limit on it.

---

## 2. Why P2 is affordable — the finding that unblocked the design

v1 keeps its hot path in bash on the theory that `PostToolUse` fires constantly
and a nu spawn is far too expensive to run per tool call. The first half is
measurable and turns out to be false.

Across **170 transcripts over 21 days — 18,598 tool calls**:

| | |
|---|---|
| busy seconds carrying exactly one event | **94%** (16,559 of 17,529) |
| most events ever seen in a single second | **6** (three times in 21 days) |
| busiest minute ever recorded | 85 |
| per agent | ~2.1/min, median gap 6.4s |

A single agent cannot make this path hot, for a structural reason no engineering
will change: emitting a tool call costs the model seconds. Only concurrency can,
and the all-time worst concurrency observed is six events in one second.

At that worst-ever burst an all-nushell hot path costs ~90ms of CPU — **9% of one
core, for one second, three times in three weeks**. The bash gate's saving in that
same second is 2.3% of a core. It was optimising a non-problem.

**Consequence: the bash fast path is deleted, and `PostToolUse` keeps its exact
semantics.** No TTL heuristic, no demotion timer, no lag anywhere.

---

## 3. The measured baseline

Measured on this machine (Apple M3, 4P+4E), nushell 0.115.1, warm, p50 of 15–40
rounds unless noted. Harness: see §8.

### Process floor — wall time per spawn

| | ms |
|---|---|
| `/usr/bin/true` | 1.53 |
| `bash -c ''` | 1.92 |
| `nu -n --no-std-lib -c ''` | **12.86** |
| `nu -n -c ''` (std lib) | 16.01 |
| `nu -c ''` (+ user config.nu) | 23.33 |
| `nu -n --no-std-lib --plugins skim -c ''` | 19.01 |

> **Implication.** The floor is ~13ms and nothing we write can lower it. What a
> design controls is the *number of processes per event*, not the work inside one.
> Loading the user's `config.nu` costs +10.5ms; the std lib +3.2ms; the plugin
> registry +6.2ms. Entry points take `-n --no-std-lib` and pay none of it.

### Parse cost — `use` is charged by reachable source, not by what you import

| `-c` payload | Δ over empty (ms) |
|---|---|
| leaf `lib/state.nu` (1.0KB) | +0.04 |
| leaf `lib/store.nu` (1.9KB) | +0.30 |
| leaf `lib/view.nu` (4.5KB) | +0.82 |
| `use ai/agent-notify list` — *selective import* | +15.6 |
| `use ai/agent-notify` — whole module | ≈ +17 |
| `use ai` — **what every v1 hook pays today** | +19.4 |

Slope from synthetic modules: **0.26 ms/KB of code, 0.029 ms/KB of comments**
(~4KB of code per millisecond). Validated against the real tree: 69.5KB predicts
17.4ms, measured 19.4ms.

> **Implications.**
> 1. **Selective import is not a lever.** Importing one command from a module
>    parses the whole module — same cost as importing all of it. Only the *file*
>    you point `use` at, and its transitive cone, matters.
> 2. **Comments are ~9× cheaper than code**, so this repo's documentation style
>    costs essentially nothing and is preserved without compromise.
> 3. **Deep submodule nesting is free** as long as the hot entry's dependency cone
>    stays narrow — the modularization preference and performance do not conflict.
> 4. **`use` is parse-time.** Nushell: *"module files and their paths must be
>    available before your script is run as parsing occurs before anything is
>    evaluated."* There is no runtime import. This single fact shapes §4.4.

### Store I/O — negligible

| | ms |
|---|---|
| `store get` (one record) | 0.08 |
| `open --raw \| from json` | 0.06 |
| `store put` (atomic: save + mv) | 0.26 |
| `to json` (one record) | 0.04 |
| `store list` | 0.39 (1 rec) → 3.48 (50 recs), ~0.065/record |

### Config file read — free, any format

`open config.yaml` 0.06 · `.json` 0.07 · `.toml` 0.06 · `.nuon` 0.09 ·
`path exists` on a missing file 0.01.

### The outside world — where the money actually goes

| | ms |
|---|---|
| `zellij action list-panes -t -j` | **11.45** |
| `zellij action rename-pane` | **10.91** |
| `zellij list-sessions -n` | 10.15 |
| `sketchybar --trigger` | 3.50 |
| `sketchybar --set` 1 property | 3.59 |
| `sketchybar --set` 50 properties | 4.12 |
| `sketchybar --set` 200 properties | 6.01 |
| `pandoc -f gfm -t plain` | **25.13** |

> **Implications.** A zellij CLI call costs nearly a whole nu startup — it is the
> most expensive operation in the system, and every zellij question becomes "can
> we avoid calling it?". A sketchybar message is cheap and barely scales with
> size, so: one large message per paint, never several small ones. pandoc is
> indefensible on an event path.

### v1 end-to-end — the baseline to beat

| | ms |
|---|---|
| `hook.sh working` — bash fast path | 3.9 (≈2 net of harness spawn) |
| the same gate implemented in nu | 36.5 |
| full event, no pandoc | **58.7** |
| full event, markdown → pandoc | **86.8** |
| the bar repaint that follows | **+34.6** |

A v1 state change therefore costs ~93ms across two nu processes. Of the 86.8ms
writer, **47.5ms is avoidable subprocess work**: `list-panes` 11.5 + `rename-pane`
11 + pandoc 25.

### v2 projection

| | ms | |
|---|---|---|
| `PostToolUse` re-assert, `changed: false` | **21.3** | measured, step 2 |
| `Stop` — a real state transition | **22.2** | measured, step 2 |
| an event we do not subscribe to | 20.9 | measured, step 2 |
| + a pane rename, once zellij lands | ~33 | projected (11ms per zellij call) |

Against v1: **2.6× cheaper** on a state change (58.7ms), **3.9×** when v1 pays for
pandoc (86.8ms), and that is before counting the second nu process v1 spawns to
repaint (+34.6ms) which v2 does not have.

The honest other side: for the COMMON event — a redundant `PostToolUse` — v1's
bash gate costs 3.9ms and v2 costs 21.3ms. That is the price of P2, and it is the
trade §2 measured before accepting: at the worst burst ever observed (6 in one
second) it is 13% of one core for one second, and at the real rate it is 37ms of
extra CPU per agent per minute — 0.06% of a core.

> Measured under load, with the floor drifted to ~14.6ms from the 12.86ms of §3
> (this machine was busy running the suites). On a quiet machine subtract ~2ms.

> Revised after step 1, upward and honestly. The original projection assumed a
> ~3ms hot cone; the store alone measures **+1.76ms** of parse, so a realistic
> full cone (core + view + dispatch + two integration hot halves) is 4–6ms rather
> than 3. The conclusion is unaffected — v1's single `use ai` costs +19.4ms — but
> the budget is tighter than first claimed, and every later step should watch it.

---

## 4. Architecture

### 4.1 The store is the core — and it holds facts, not decisions

```
$XDG_DATA_HOME/agent-notify/
  agents/<id>.json          one file per agent instance
```

One namespace. One file per agent, so concurrent agents never contend; writes are
temp+rename, so a reader never sees half a record. (Both inherited from v1, which
got this right.)

**Records hold facts. Display decisions are derived at read time.** v1 bakes a
decision into storage — an eight-line ladder picks *which* base name wins, freezes
it into `pane_name`, and guards it with `pane_locked`. v2 stores both facts
(`name`, what the agent called itself, write-once; `name_auto`, the cwd basename,
last-wins) and resolves precedence in the view. Derivation costs 0.04ms, so there
is no reason to bake a decision into storage where a later change of mind would
need a migration to undo.

**The schema is open, with a small core and one namespace per owner.** A closed
schema would make the core depend on every integration's fields — adding an
integration would mean editing core — which contradicts P4's opt-in requirement.
So the core guarantees a handful of fields and owns their policy; everything else
belongs to a namespace named after its owner, integration or client alike.

```nu
{ # ── core-owned ──────────────────────────────────────────────────────────
  id: "6923c0bc-…"        # caller-supplied, opaque, unique per agent instance
  client: "claude"        # who is reporting
  state: "awaiting"       # CLOSED vocabulary: working | awaiting |
                          #                    needs-attention | idle
  state_since: <datetime> # stamped only when `state` actually changes
  updated_at: <datetime>  # bookkeeping — EXCLUDED from the `changed` comparison

  # ── common facts, core-declared, all optional ───────────────────────────
  name: "explain-agent-notify"
  cwd: "/Users/colombos/projects/…"
  message: "…as the agent wrote it…"

  # ── namespaces, each owned entirely by the named owner ──────────────────
  zellij: { session: …, pane_id: …, tab_id: …, tab_position: …,
            tab_name: …, title_written: …, context_read_at: <datetime> }
  claude: { transcript_path: …, source: … } }
```

**Identity is the agent, not the pane.** v1 keys on `(zellij_session, pane_id)`,
so its store cannot exist without zellij — incompatible with zellij being opt-in.
The key is the reporting agent's own session id, whatever shape that takes (P5).

Because the id is opaque, the **filename derivation must be injective**: anything
outside `[A-Za-z0-9._-]` is percent-encoded, so the common case stays greppable
and no two ids can collide onto one file. (v1's `str replace '/' '_'` collides
`a/b` with `a_b`.) The record carries its own `id`, so a filename never needs
decoding.

**One guarantee the pane key gave us for free is now merely a fact:** "one pane,
one agent" can be violated — a crashed session's stale record and a fresh one can
both claim pane 3. The core does not resolve this, because the core must not know
what a pane is; the zellij projection picks the live record and the janitor drops
the dead one.

### 4.2 Writing — `patch` and the `changed` flag

```nu
store get   <id>                → record | null
store patch <id> <changes>      → {changed: bool, before: record, after: record}
store set   <id> <record>       → replace wholesale
store drop  <id>
store list  [--where <closure>] → all records
```

**`patch` returning `changed` is the load-bearing decision of the whole design.**
It performs the read-merge-write atomically, enforces field policy, and reports
whether the world actually moved — comparing *semantic* fields only, ignoring the
`updated_at`/`state_since` stamps it sets itself.

That one boolean replaces three separate mechanisms in v1 — the bash fast-path
gate, the `working` verb's early return, and the render-side model cache — with a
single check in the one place able to answer it. When it comes back false the
event ends: no zellij, no sketchybar, ~15ms, nothing touched.

Field policy is the only cleverness the store gets, and it is a handful of lines:
the schema names write-once fields, `patch` drops writes to a field already set,
and it stamps `state_since` only when `state` genuinely changes.

### 4.3 Reading — one contract, per integration

```nu
project [records: list<record>]     # paint what changed. Never reads the store.
```

The core reads the store **once** and hands the same snapshot to every enabled
integration — not for the 0.39ms, but because it guarantees every surface paints
the same instant. An integration that never reads the store is also trivially
testable: call `project` with a hand-written list, no agent, no hook, no zellij.

Ordering rules:

1. **Persist first, project after.** A projection failure must never lose a fact.
2. **Each integration is wrapped in `try`** — a dead zellij cannot stop the bar.
3. **`patch` does not dispatch.** Otherwise `core/store.nu` would depend on the
   integrations and stop being a cheap leaf that anything can import. The *entry
   point* sequences patch-then-dispatch, so a CLI write projects exactly like a
   hook does and the surfaces can never diverge from the store.

### 4.4 Hot and cold — the layout consequence of parse-time `use`

Because the hot entry pays for everything it imports, every integration splits
into a hot half and a cold half **at file boundaries**, by one question: *does an
event need this?*

```
agent-notify2/
  mod.nu                    facade — re-exports the public surface
  hot.nu                    THE event entry. Narrow cone, nothing cold reachable.
  cli.nu             COLD   human/admin command surface
  core/
    schema.nu               record shape, states, field policy, version
    paths.nu                XDG paths
    store.nu                get/patch/set/drop/list — pure state, no I/O beyond it
    config.nu               read/normalize/validate the YAML (strict)
    dispatch.nu             fan out to enabled integrations
    janitor.nu       COLD   liveness + reconciliation (the 30s timer)
  view/                     presentation-neutral derivation shared by all surfaces
  clients/
    claude.nu               hook payload → store changes
  integrations/
    zellij/
      project.nu     HOT    titles
      admin.nu       COLD   liveness source, jump, install
    sketchybar/
      project.nu     HOT    model → one message
      items.nu       HOT    pure model→args builders
      theme.nu       HOT    palette/geometry, defaults overridable from config
      install.nu     COLD   item pool, click/hover wiring, teardown
    picker/          COLD   the terminal drawer (`browse`)
```

Hot cone budget: **4–6ms**, of which the store already spends 1.76 (measured in
step 1). Every KB of cold code kept out of it is 0.26ms — so the split has a
number behind it, not just taste — and comments are ~9× cheaper than code, so the
documentation is not what costs.

**Opt-in is about behaviour, not parse cost.** `use` being parse-time means the
hot entry imports every integration's hot half unconditionally; config gates the
*calls*. A disabled integration touches nothing and may be absent from the machine
entirely, but it still costs its ~1ms of parse. Making that zero would require a
generated entry point, which we are not doing unless numbers ever demand it.

### 4.5 Configuration

**`$XDG_CONFIG_HOME/agent-notify/config.yaml`** — data, read at runtime.

Resolution order: `$env.AGENT_NOTIFY_CONFIG` (path override, for tests and for
running v2 beside v1) → the XDG path → built-in defaults. An absent file is a
clean fallback, because `open` is a runtime read.

This deliberately departs from the house convention (`$env.gg_config`,
`$env.kubebridge_config`, `$env.ai_config`) for a principled reason worth
recording in the module header: those modules are typed at a prompt by a human in
a configured shell. agent-notify is invoked by Claude Code, by sketchybar, by
zellij — processes with no shell config, and `nu -n` cannot see `$env` set in
`config.nu`. A `source`-based bridge would work but is parse-time: a missing file
becomes a parse failure, and the path cannot be chosen at runtime. `open` has
neither problem and costs 0.06ms.

**What stays in `config.nu`:** closures only — `$env.ai_config.picker` (skim) and
`.render` (bat), used by the interactive picker, wired by `module-hooks.nu`
exactly as today. Data in the file, code in the env.

Colours live in the config file. Validation is **strict**: an unknown integration
name or a malformed entry is an error with a helpful message, not a silent no-op,
because a hand-edited file makes typos likelier than an env record does. A
`config show` command prints the resolved record and the file it came from.

### 4.6 Clients — one module per agent

The agents that might report into the store agree on almost nothing. Surveyed
before committing to a shape:

| agent | wiring | payload transport | event named by | identity | reply contract | states reachable |
|---|---|---|---|---|---|---|
| Claude Code | `settings.json` hooks, one per event | **stdin** JSON | our argv | `session_id` + env var | silence fine; exit 2 blocks | all four |
| Codex `hooks` | `hooks.json` / `[hooks]` | stdin JSON | `hook_event_name` *in* the payload | `session_id` | silence fine; exit 2 blocks | all four |
| Codex `notify` *(superseded)* | `config.toml` `notify = [argv]` | **argv** JSON | `type` *in* the payload | `thread-id` (kebab-case) | ignored | `awaiting` only |
| Gemini CLI | `settings.json` hooks | stdin JSON | our argv | `session_id` | **must print valid JSON** | all four |
| Cursor CLI | `hooks.json` | stdin JSON | per-event | — | exit codes can block | `cursor-agent` emits shell events only |
| Goose | plugin `hooks/hooks.json` | stdin JSON | event name *in* payload | in payload | — | tool-level |
| OpenCode | JS/TS **plugin module** | not a command | JS callback | via JS API | — | needs a shim plugin |
| Aider | `notifications_command` | **nothing** | implicit | **none** | — | `awaiting` only |

Five axes vary: **transport**, **how the event is named**, **field naming and
identity**, **the reply contract**, and **how much of our state vocabulary the
agent can even reach**. A declarative mapping table could encode the first three.
It cannot encode the fourth (Gemini must print `{}` where Claude must print
nothing), and it cannot encode Aider, which supplies no identity at all and needs
its client to invent one. Encoding all of it would have produced a worse nushell.

So: **one file per agent**, exposing three things.

```nu
export const INFO = {name, title, transport, states}   # for `agent-notify2 clients`
export def map [event: string, payload: record] -> operation   # PURE — where the thinking is
export def main [...]                                          # the entry; owns the peculiar parts
```

`map` is a pure function, which is why 30 of Claude's 37 assertions need no store,
no hook and no agent. `main` owns transport, reply and exit code — the parts that
are strange per agent, expressed where strange is cheap.

**Nothing registers a client.** The agent's own configuration names the file
directly, so a client works the moment it exists. `clients/mod.nu` lists the
shipped ones for `agent-notify2 clients` and for nothing else; an entry point
imports exactly the one client it is for and pays to parse no other.

**A half-wired agent is worse than an unwired one.** Codex shipped here as a
`notify` client first, and `notify` fires once, when a turn ends. That reached one
of the four states, so a Codex record read `awaiting` from its first turn to its
last — true only where it happened to coincide with reality, and wrong every
second the agent was working. Nothing was malformed: a legal state, a legal
client, validation passing. The store has no way to say *I don't know*, so a
one-sided hook writes a confident fact that outlives its truth, and the counter a
surface exists to show — "2 agents waiting for you" — stops being worth a glance.
The order of preference when an agent under-reports:

1. **Fix the transport.** If a state is reachable at all, carry the fact rather
   than a guess about it. Codex's hooks reach all four, which is what the client
   uses now.
2. **Let the surface read `INFO.states`.** Every record names its `client`, so a
   surface can join to that client's declared reach and decline to count what it
   cannot know. This is what makes the field load-bearing rather than decorative,
   and it is the only answer for an agent like Aider that supplies nothing.
3. **Decay from `state_since`.** Catches the opposite failure — an agent stuck in
   `working` because its end-of-turn hook never fired. Useless for this one:
   `awaiting` is a resting state, so age says nothing against it.

**One transport per agent**, even when the agent offers several. Codex has both
`notify` and hooks, and they identify an agent differently — `thread-id` against
`session_id`, with nothing establishing that those are the same value. Running
both would risk two records for one agent: the same pane counted as working and
awaiting at once. A client takes the transport that reaches the most states and
ignores the rest.

**Wiring is printed, not applied.** `agent-notify2 clients wiring codex` prints
the block to paste. Merging into four foreign configs in three formats — with
backups, pre-existing entries and an uninstall path — is a great deal of blast
radius for the convenience of not pasting a block yourself.

---

## 5. Decisions

| # | Decision | Status | Why |
|---|---|---|---|
| D1 | No bash anywhere; all logic in nushell | **LOCKED** | §2 — the gate saves 2.3% of a core in the worst second in 21 days |
| D2 | `PostToolUse` keeps exact semantics; no TTL/demotion heuristic | **LOCKED** | follows from D1 — the rate never justified the trade |
| D3 | Config at `$XDG_CONFIG_HOME/agent-notify/config.yaml` | **LOCKED** | runtime read, entry-point agnostic, 0.06ms |
| D4 | Colours in the config file | **LOCKED** | user decision |
| D5 | Strict config validation | **LOCKED** | user decision |
| D6 | No animations — static glyphs, coloured by state | **LOCKED** | user decision; also removes the only 1Hz process (~15ms/s forever) |
| D7 | No surface/render cache, no `surfaces/` namespace | **LOCKED** | saves ~2.4ms in a rare case; costs a namespace, a staleness class, and a concurrency race |
| D8 | One store namespace: `agents/`, one file per agent, temp+rename | **LOCKED** | inherited from v1, measured cheap (0.26ms put) |
| D9 | In-process dispatch — no poke, no `render.sh`, no second process | PROPOSED | removes a whole nu spawn + parse: 34.6ms/event measured |
| D10 | No daemon | PROPOSED | at ~1 event/s, saving the 12.9ms floor cannot justify the lifecycle risk |
| D11 | Identity = the agent's session id, opaque and caller-supplied | **LOCKED** | the only way zellij can genuinely be opt-in; opaque because of P5 |
| D11b | Agent-agnostic: any agent may call the entry points; Claude is one client among N | **LOCKED** | P5 |
| D11c | Open schema — small core + one namespace per owner | **LOCKED** | a closed schema would make core depend on every integration |
| D11d | Closed, core-owned state vocabulary | **LOCKED** | surfaces cannot render a state they have never heard of |
| D11e | Injective id → filename encoding (percent-encode outside `[A-Za-z0-9._-]`) | **LOCKED** | opaque ids may contain anything; v1's mapping collides |
| D12 | Facts not decisions: `name` + `name_auto`, precedence in the view | PROPOSED | removes v1's base-name ladder and `pane_locked` |
| D13 | Lazy zellij reads: skip renames via `title_written`; read tab context only when a tab write is pending, throttled by `context_read_at` | PROPOSED | 11ms is the most expensive call in the system |
| D14 | Store the message as written; derive the flattened form at paint time | PROPOSED | depends on D15 |
| D18 | One client MODULE per agent, not a declarative mapping table | **LOCKED** | §4.6 — transport, reply contract and identity all vary; a map would become a worse nushell |
| D19 | Clients are discovered by the agent's own config naming the file; no registry | **LOCKED** | adding an agent is one new file |
| D20 | Wiring is printed, never applied | **LOCKED** | four foreign configs in three formats |
| D21 | A client uses ONE transport, even when its agent offers several | **LOCKED** | §4.6 — Codex's `notify` and hooks key on different ids; running both double-counts one agent |
| D22 | Fix an agent's transport before inferring states it does not report | **LOCKED** | §4.6 — the store must not hold a confident fact nothing supports |
| D15 | Replace pandoc with a nu-native flattener | **OPEN** | 25.1ms on the event path, and a dependency |
| D16 | Where the bench harness lives | **OPEN** | ~350 lines of documented nu; §8 |
| D17 | Final promoted name/location (top-level `agent-notify`?) | **OPEN** | v1 is `ai/agent-notify`; v2 is top-level |

---

## 6. Explicitly rejected

Recorded so they are not reinvented:

- **A bash (or any non-nu) fast path** — §2.
- **A long-lived projector daemon** — the floor it saves is 12.9ms on an event
  that happens about once a second; the failure modes (dead daemon, blocked
  writer, crash recovery) are worse than the problem.
- **The SketchyBar poke (`--trigger` → `render.sh` → a second nu)** — in-process
  dispatch does the same work 34.6ms cheaper and deletes two glue scripts and two
  custom events.
- **An append-only event log** — records plus timestamps answer every question a
  consumer has today; a log needs compaction and has no reader. Additive later.
- **A render/model cache** — D7.
- **Selective imports as a performance technique** — measured identical to
  importing the whole module.
- **Running hooks with the user's full `config.nu`** — +10.5ms/event, grows with
  the config, and couples every agent's hooks to the shell config being healthy.

---

## 7. Inherited from v1 — things it got right, to be kept

- Per-agent record files; atomic temp+rename writes.
- **A tab's base name belongs to the user**, not to us: read it back from the live
  tab title with markers stripped, so a manual rename is honoured and the last
  agent leaving cannot erase it.
- **Glyphs distinguish states by shape alone**, because zellij titles carry no
  colour; the same shapes take the state hue on the bar.
- **A fixed SketchyBar item pool** created once, `--set`-only thereafter. v1
  attributes this to `--add`/`--remove` costing the daemon ~20ms of relayout each
  — *that figure is v1's, not ours, and is the one inherited claim to re-measure
  when we build the integration.*
- **One derivation shared by every surface** (`view/`), so the bar and the picker
  cannot drift apart.
- A blank projection **drops** our name rather than writing an empty one.
- Liveness is all-or-nothing: an unreadable zellij means "don't prune", never
  "everything died".

---

## 8. Method

Performance claims in this document are reproducible. The harness measures three
different things three different ways, because they are not interchangeable:

- **wall** — per-spawn latency distribution (p50/p95; spawn latency is
  right-skewed and a mean hides the tail).
- **cpu** — user+sys including descendants, amortised over N spawns inside one
  `/usr/bin/time` wrapper, because macOS reports 10ms granularity and a single
  15ms process is otherwise unmeasurable.
- **span** — nushell's own `--log-level perf` attribution, which separates
  `evaluate_commands` (parse + eval of our code) from fixed runtime overhead.

Every spawn case is warmed first — a cold 40MB binary measures 11.2ms where steady
state is 7.4ms — and `/usr/bin/true` is always measured as the floor everything
else sits on.

Each implementation step re-runs the harness and records its numbers against the
§3 baseline, so a regression is caught when it is introduced rather than at the end.

Both live in the repo, and neither is part of the module — nothing in `mod.nu`
imports them, so `use agent-notify2` never parses a byte of either:

```
agent-notify2/bench/      use agent-notify2/bench   → bench floor | parse | work | rate | v1
agent-notify2/tests/      nu agent-notify2/tests/store.nu        (no -I needed)
```

---

## 9. Steps

Each step: discuss the design → implement → verify against a stated done-when, and
re-measure. v1 keeps running untouched throughout; v2 uses its own store dir and
its own bar item names so both can be live at once.

0. **Baseline** — ✅ done (§3).
1. **Core store** — ✅ done. `core/paths.nu` + `core/schema.nu` + `core/store.nu`,
   with the command surface in `cli/store.nu`. 32/32 checks pass; the hot cone
   parses in +1.76ms; a foreign process reports with
   `echo '{…}' | nu -c '… store patch <id> --stdin'` and reads back with
   `| to json`. Two things the suite caught that review had not: an id beginning
   with `.` (`../../etc/passwd` strips to `....etcpasswd`) produced a *hidden*
   file — written, readable by id, and invisible to every surface; and naming a
   command `get` silently shadows the builtin for every imported module (§10).
2. **Claude client + the entry point** — ✅ built and verified (37/37), not yet
   wired into `settings.json`. `clients/claude/adapt.nu` is a pure payload→operation
   mapping; `clients/claude/hook.nu` is the entry; `core/event.nu` holds the
   sequence and the dispatch seam; `core/identity.nu` answers "which agent am I";
   `cli/agent.nu` adds `report` and `name`. 21.3ms per event. Three findings:
   subagent tool calls carry the PARENT's session id (so they fold in for free,
   and `SubagentStop` must be ignored); `StopFailure` gives us a state v1 could
   not express; and importing the entry with `-c` rather than running it as a
   script saves ~9ms per event (§10).
2b. **The client contract, proved on a second agent** — ✅ done. `clients/claude.nu`
   and `clients/codex.nu`, one file each; `core/payload.nu` holds the two
   transports; `agent-notify2 clients [wiring <name>]` lists and explains them.
   85/85 across three suites, 22.8ms per event (unchanged by the refactor). Codex
   was chosen precisely because it shares almost nothing with Claude — argv
   transport, script entry, event name inside the payload, kebab-case fields, one
   reachable state — so the contract is proved rather than assumed. (The argv
   half of that is superseded by 2c; the contract it proved is not.)
2c. **Codex moved to the hook transport** — ✅ done. `notify` reached exactly one
   state, so a Codex record read `awaiting` for its whole life — a confident fact
   that outlived its truth (§4.6). Codex's hook system turns out to be
   Claude-shaped — stdin JSON, `session_id` / `cwd` / `hook_event_name`, matcher
   groups, exit 2 to block — so the client now subscribes to six events and reaches
   all four states, and `notify` is gone rather than kept as a fallback (D21). The
   one shape difference from Claude: the event name comes from the body rather than
   our argv, which gives a single command string for all six subscriptions and no
   way for an argument to disagree with the key it is registered under.
   103/103 across three suites, 20.7ms per event. `core/payload.nu` lost
   `from-args` along with its last caller — an argv agent can read its own argv in
   one line, and untested code in the core is worse than a line rewritten later.
   Written from documentation rather than observed traffic (Codex is not installed
   here), which the client's header says plainly. The suite immediately found a
   store bug no surface had reached yet: `list` on an *emptied* store errored,
   because a glob that matches nothing is an error (§10).
3. **Config + dispatch** — strict YAML loading, the opt-in list, fan-out. Deferred
   to here deliberately: config is almost entirely *integration* settings, and
   until a surface exists there is nothing concrete to configure.
4. **zellij integration** — titles, with D13's lazy reads, on live data.
5. **SketchyBar integration** — model, one-message paint, install owning its own
   glue and item pool. Re-measure the `--add`/`--remove` claim here.
6. **Picker + jump** — the terminal surface and the actions, on the shared `view/`.
7. **Cutover** — store migration, hook flip, delete v1, rename, update
   `settings.json` / `sketchybarrc` / `config.kdl`.

> **Reordered after step 1** (was: write API → config → zellij → client). Two
> reasons. The old step 2 largely landed inside step 1 — `patch`, `changed` and
> validation are done, and what remains of it (write-once policy, `view/`) belongs
> to the steps that actually need it. And the old order built a surface before
> anything fed it, so zellij would have been judged against hand-written fixtures.
> The distinction that settles it: **writers need no opt-in, surfaces do.** An
> agent reporting itself just calls the command; there is nothing to enable. So
> the client can land before config, and config can wait until a surface makes it
> concrete.

---

## 10. Nushell notes (hard-won)

Things that cost time once and should not cost it twice. All verified on 0.115.1.

**A def named after a builtin shadows that builtin for every module the file
imports** — whatever the order of the `use` statements, and the error surfaces
somewhere else entirely. `core/store.nu` defining `export def get` made
`core/schema.nu` fail to parse on `get -o $f` with "the `get` command doesn't have
flag `-o`", a file that never mentions `get` as a name. Worse, a *bare* `get $x`
in that position would not error at all — it would silently call ours.

| | |
|---|---|
| `export def get` (before or after `use`) | poisons imported modules |
| `export def read` | fine |
| `export def "store get"` | **fine** — multi-word subcommands are exempt |

So: library functions avoid builtin names (`read`/`remove`, not `get`/`drop`),
and the command surface uses multi-word names, which is what we wanted it to read
as anyway. Only `get` and `drop` collide among the verbs this module wants;
`set`, `list`, `patch`, `read`, `remove` and `write` are all free.

**`use` is parse-time.** *"module files and their paths must be available before
your script is run as parsing occurs before anything is evaluated."* There is no
runtime import — which is why opt-in integrations gate calls rather than imports
(§4.4), and why configuration is a data file read with `open` rather than a
nushell file pulled in with `source` (§4.5).

**`to json` renders a datetime with the local offset**, so a record written in
Rome and read in UTC would differ textually. Timestamps are stored as explicit
UTC ISO-8601 strings, which also makes lexicographic order chronological.

**Records compare structurally and order-insensitively** (`{a:1,b:2} == {b:2,a:1}`
is true, nested too), which is what lets `changed` be a plain `!=` rather than a
canonicalising walk.

**Running a file as a script with `main` + arguments costs ~7.5ms more than the
same file imported as a module**, because nu evaluates twice — a synthetic command
line on top of the file itself (`eval_source <commandline>` nested inside
`evaluate_file`, visible under `--log-level perf`). A script with only top-level
code does not pay it. Measured on the real entry: 29.3ms as a script against
20.4ms via `-c 'use <abs path>; hook <Event>'`, which is why the hook command line
is spelled the second way.

> That rule bit three times in one afternoon while writing the clients: `def
> ignore` (shadowing the builtin the next line pipes to), `export def all` in the
> test runner, and `export def get` in step 1. It is the sharpest edge in the
> language as far as this module is concerned. A related one: **a module cannot
> export a command with its own name** — `clients.nu` must export `main`, not
> `clients`.

**Reading stdin blocks until the writer closes it.** `open --raw /dev/stdin` in an
entry point run by hand hangs with no clue why; `is-terminal --stdin` guards it.

**`ls` on a glob that matches nothing is an ERROR**, not an empty list — and a
directory that outlives its contents is the ordinary case for a store whose last
agent has just ended. `try { ls … } catch { [] }`, or the first empty store takes
every surface down with it.

**`reject` errors on a missing column**; `reject --optional` does not.

**Intermediate pipelines print nothing under `nu -c`** — only the final one — so
anything a script means to show needs an explicit `print`.
