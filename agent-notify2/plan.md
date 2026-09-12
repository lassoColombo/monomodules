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

### 4.6b Liveness — proving an agent is gone

Records are dropped by `SessionEnd`, so the only leaks come from agents that never
got to say goodbye: a killed process, a crash, a closed pane, a closed terminal.

**An agent is a process.** If its process is gone, the agent is gone. Every other
signal is a proxy, and every proxy is wrong somewhere:

| proxy | wrong when |
|---|---|
| the zellij pane exists | the agent is killed and the pane stays open |
| the record was updated recently | the agent is idle, waiting for you |
| the transcript file exists | the file outlives the session that wrote it |

Nobody hands us the pid, so we find it: a hook is STARTED BY the agent, which
makes it a descendant, and a descendant can ask who started it.

```
83758  nu                         ← the hook
83572  /bin/zsh                   ← the shell Claude ran the command with
3234   /opt/homebrew/bin/claude   ← the agent
2837   nu                         ← the pane's shell
907    /opt/homebrew/bin/zellij
```

The parent is no use (that shell dies when the hook returns) and the number of
steps is not fixed (an agent running the command directly has one fewer), so we
climb until we meet the name **the client declares** — `process: "claude"` in
`clients/claude.nu`, which is where agent-specific knowledge already lives.
`$env.AGENT_NOTIFY_PID` short-circuits the walk, the same escape hatch
`AGENT_NOTIFY_ID` gives for identity (P5).

Stored as `proc: {pid, started}` at `SessionStart` — where it can be new — and
looked up again on `UserPromptSubmit`, once per turn. **That retry is what stops a
missing pid being permanent**: if the walk fails once, or the session predates
this code, that agent could otherwise never be proved dead for the rest of its
life and every surface would show it forever. No store read is needed to decide
whether it is missing, because attaching it is idempotent — a pid does not change
within a session, so a second attach produces an identical record, `changed` is
false, and nothing is written or painted. Measured: `UserPromptSubmit` 28.5ms →
40.2ms, once per turn; `PostToolUse`, which fires hundreds of times, is
untouched at 29ms. The start time is not decoration: pids are recycled, so a
number alone would eventually match a stranger's process and keep a dead agent
alive forever. A number *and* the second it started cannot be confused.

The check is one `ps` for every recorded pid at once. Present with a matching
start time → alive. Absent → **proof** → drop.

**The safety rail: we cannot tell → we drop nothing.** That covers a record with
no `proc` (its SessionStart predates this, or its agent could not be located) and
a `ps` that failed to answer. One unreadable answer must never wipe a live store.

**One extra case.** `/clear` does not end the process — the same agent starts a
fresh session inside it, so two records can name one genuinely live pid. A process
runs one session at a time, so among records sharing a live pid only the most
recently updated survives.

Never on a hook: `ps` costs ~13ms and a hook could do nothing with the answer. It
runs from `store prune`, from `surfaces refresh`, and later from the picker.

**The prune hands its casualties to the repaint.** `janitor prune` returns the
WHOLE records it removed, and `surfaces refresh` passes them to dispatch as
`--gone`, which folds them into "what the store looked like a moment ago". Without
that, `--force` meant "pretend nothing was there before" and a surface could not
tell what had disappeared: an agent killed in a pane that OUTLIVED it kept its
title for good. SketchyBar never noticed the bug — a counter is recomputed whole
every time — which is exactly why it had to be found on zellij.

What it deliberately cannot do: a **hung** agent stays, which is correct — it
really is still there. And an agent whose `SessionStart` we missed has no `proc`
and can never be pruned.

### 4.6c The clock — who looks when nobody reports

The store is **pushed, never polled**: an agent's hook writes it and paints the
surfaces in the same breath, which is why a repaint costs 6.5ms and needs no
daemon. But a dead agent fires no hook — that is what dead means — so its record
is never revisited and every surface keeps showing it.

So something has to look. **The tick is not a second pruning mechanism**: it runs
exactly the same pid-based `janitor prune`, then repaints. All it contributes is
the looking.

Three candidates were tried, in this order:

| clock | why not |
|---|---|
| a hidden SketchyBar item, `update_freq=30` | worked, and free — the daemon is already running. But it made a core guarantee depend on one OPTIONAL surface being installed and enabled |
| `job spawn` | a nushell job is a thread inside its process: it dies when that process exits, and so does anything it starts (both verified). A hook lives ~30ms |
| **launchd, `StartInterval`** | ✅ launchd *is* a clock. No daemon to keep alive, no lock file, no pid to supervise, no detaching trick — and it survives logout and reboot, which a spawned process would not |

`core/clock.nu` writes the job, `agent-notify2 clock install|status|uninstall`
drives it, and the tick is `surfaces refresh` — the same command a human types.
Verified end to end: a record planted with a dead pid was gone in 15 seconds.

### 4.7 Surfaces — the projection gate

A surface is a pure function from the store to what should be on screen, plus an
impure half that puts it there. Four exports, mirroring the client contract:

```nu
export const INFO = {name, title}
export def settings [given: record, me: any] -> record # strict; defaults; ambient
export def project [records, settings] -> any          # PURE — the thinking
export def apply [desired, settings] -> any            # side effect; returns what it learned
```

`settings` gathers everything the surface needs to know before it thinks: its
config namespace, `me` (the agent this event is about, handed down by dispatch,
which knows it exactly where the environment would be a guess), and anything else
ambient. Gathering it once is what keeps `project` pure enough to run twice.

**The gate.** Dispatch runs the pure half TWICE — once against the store as it
was, once as it is — and touches nothing when the two agree:

```
project(before) == project(after)   →  do nothing
```

That single comparison is the performance story. A `Stop` changes `message`, but
a pane title has no message in it, so the projection is identical and zellij —
11ms of subprocess, twice — is never called. v1 reached the same place with a
bash fast-path gate, a separate rule for SketchyBar and a janitor to re-check;
here every future surface inherits it for free, with no cache, no TTL and nothing
remembered between events. It is also why `project` must be pure: an impure one
could not be run twice.

**Dispatch runs inside the agent's process**, so a surface inherits the agent's
environment — which is how the zellij surface will learn its pane id without the
core ever hearing the word zellij. A daemon would have to be told.

**Surfaces are a table of closures**, built by hand in `core/dispatch.nu`, because
`use` is parse-time and nushell has no first-class modules: a name cannot become a
module at runtime. Passing a different table is what lets the tests exercise all
of it with nothing installed (`tests/fake.nu`).

**A side effect is built as data first.** `project` returns what should be shown;
a surface that talks to a program also exposes the *message* it would send as a
pure function, and `apply` is then two lines that send it. The SketchyBar suite
runs 33 checks with no bar installed and not one subprocess, and asserts the exact
arguments the daemon would receive.

**A surface never writes the store.** It returns what it learned — where its pane
is, which item it was given — and dispatch records that in the surface's own
namespace. The store stays the one thing that owns writing, and the surface stays
a LEAF of the import tree, which is not a stylistic point: nushell parses a module
once per import path, so a store reached both directly and through a surface is
parsed twice on every event (§10). Removing that one diamond took the machinery
from 5.28ms to 3.87ms.

**Nothing in the dispatch path may throw.** It runs after the store has committed.
Each surface is wrapped alone, so one failing cannot stop the next, and a broken
config degrades to "no surfaces" rather than to a broken hook.

The config file has **the same shape as a store record**: a small core the module
owns, one namespace per owner, unknown keys rejected. One idea, two files.

```yaml
surfaces: [zellij, sketchybar]     # the opt-in list; its order is dispatch order
zellij:
  glyphs: {working: 🧠, awaiting: 🔔}
```

A namespace for a surface that is merely switched off is fine — disabling should
not mean deleting your colours. A namespace naming a surface that does not exist
is an error, because that is a typo.

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
| D23 | The projection gate: compare `project(before)` with `project(after)` | **LOCKED** | §4.7 — replaces v1's bash gate, trigger dedup and janitor with one comparison, and no state |
| D24 | Strict config validation in the CLI, never in the hook | **LOCKED** | §4.7 — a YAML typo must not be able to stop the store recording facts |
| D25 | The readers are `surfaces/`, the writers are `clients/` | **LOCKED** | "integration" covers both halves; these two words do not |
| D26 | Surfaces reach dispatch as a hand-written table of closures | **LOCKED** | `use` is parse-time; it is also what makes them testable with nothing installed |
| D27 | A surface reports what it learned; dispatch writes it | **LOCKED** | §4.7 — one writer, and it keeps surfaces out of the store's import cone |
| D28 | A pane's name comes from the store, never from parsing its old title | **LOCKED** | user decision; deletes ~60 lines of v1 and one zellij call per event. A manual rename is overwritten |
| D29 | The import cone must be a TREE | **LOCKED** | §10 — a diamond is parsed twice, on every event, forever |
| D30 | Liveness is the agent's PROCESS, recorded once at SessionStart | **LOCKED** | §4.6b — the only signal that is proof rather than a proxy; replaces v1's zellij scan and janitor outright |
| D31 | Cannot tell ⇒ delete nothing | **LOCKED** | §4.6b — one unreadable `ps` must never wipe a live store |
| D32 | The client declares how to find its own process | **LOCKED** | §4.6b — same rule as every other agent-specific fact (D18) |
| D33 | The hook paints the bar itself; no trigger, no daemon round trip | **LOCKED** | step 5 — dispatch already holds the store; v1's path cost a second nu (~47ms) and a glue script |
| D34 | A side effect is built as DATA first (`message`), then sent | **LOCKED** | step 5 — it is what lets the bar be tested exactly, with no bar installed and no subprocess |
| D35 | A fixed item pool, created once, never added to or removed from | **INHERITED** | v1's most expensive lesson; re-measured at 17.51ms per add+remove against 6.5ms per message |
| D36 | Every write goes through `core/event.nu`, the CLI included | **LOCKED** | step 7 — the command surface IS the public API (P5); a write that skips the seam is a surface that never hears about it |
| D37 | `apply` receives the previous projection | **LOCKED** | step 7 — the only way a surface can act on what has disappeared, and it makes "skip what did not move" free |
| D38 | Dispatch answers "whose event" and "whose environment" separately | **LOCKED** | step 7 — identical for a hook, different for a CLI write about another agent |
| D39 | The clock is its own launchd job, never a surface's item | **LOCKED** | §4.6c — a core guarantee must not depend on an optional surface being installed |
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
3. **Config + dispatch** — ✅ done. `core/config.nu` (the YAML file, strict
   `problems`, never-throwing `load`), `core/dispatch.nu` (the gate and the
   fan-out), `cli/config.nu` and `cli/surfaces.nu`, and the seam in
   `core/event.nu` is live. 139/139 across four suites. **Step 3 adds 0.76ms of
   parse to every event** — the price of §4.4's "gate calls, not imports", which
   parse-time `use` leaves no way around; two realistic surface modules (18KB,
   this repo's comment-heavy style) were measured separately at 2.07ms, so the
   budget holds through step 5. The hook is 25ms.
   `surfaces/` ships EMPTY on purpose: the contract is exercised by `tests/fake.nu`,
   a complete surface that writes a line to a file and therefore needs nothing
   installed — the same move that proved the client contract on Codex. One
   consequence for the core: `drop` now reads the record before removing it, because
   a surface cannot say whether its output changed about an agent it never saw.
4. **zellij integration** — ✅ done, panes only. `surfaces/zellij.nu`: glyph plus
   name, one call to zellij per state change and **none at all** when nothing
   visible changed. Two of v1's three calls per event are gone, for two separate
   reasons: the pane is known from the environment (dispatch runs inside the
   agent's process), and the NAME IS A FACT IN THE STORE rather than something
   parsed back out of the old title — which deletes v1's `parse-title`,
   `bare-title` and its list of legacy glyphs outright. The cost is that a manual
   pane rename is overwritten, which is the right trade when the store is the
   source of truth. 170/170 across five suites; the surface machinery costs 3.87ms
   of parse per event, the hook 28ms.
   Two findings, both in §10: a module reached by two import paths is parsed
   TWICE (fixing that one diamond saved 1.4ms per event and produced the
   leaf/report rules above), and Private Use Area glyphs do not survive ordinary
   tooling — written as literals they arrived as empty strings, and the suite
   caught it as "every state has the same title".
4c. **Liveness** — ✅ done. `core/proc.nu` (find the agent's process, ask `ps`
   which are still running) and `core/janitor.nu` (the two rules), reached by
   `agent-notify2 store prune` and by `surfaces refresh`, which now prunes before
   it repaints. 198/198 across six suites.
   Two earlier proposals were **dropped** on the way, both correctly: a zellij
   pane check (a killed agent can leave its pane open, so it proves the wrong
   thing) and a heartbeat (it existed only because I had no proof and needed a
   hint — with proof available, guessing has no job). One mechanism replaced
   three layers.
   Costs: `SessionStart` 27ms → 38.6ms for the one-time walk, every other event
   unchanged, `proc.nu` free to parse, `prune` 13ms of `ps` on a cold path.
4b. **zellij tab aggregates** — deferred deliberately. A tab's name belongs to the
   user, so a tab title cannot be computed from the store alone: it has to be
   read, stripped and put back. The real question is who owns the tab name, and
   that deserves an answer rather than a guess.
5. **SketchyBar integration** — ✅ done, the three counters.
   `surfaces/sketchybar.nu`, 233/233 across seven suites, +0.82ms of parse (the
   whole surface machinery is now +4.69ms).
   Measured first, because the numbers chose the design: `--query bar` 5.98ms,
   `--set` one property 6.59ms, **`--set` TEN properties in one message 6.54ms**,
   `--add` + `--remove` one item 17.51ms. So a message costs what a process costs
   and almost nothing per property — a whole repaint is ONE call — and v1's
   fixed-pool rule holds, since adding items is ~3× setting them.
   The big deletion is the paint path. v1 went `hook → --trigger → daemon →
   render.sh → a fresh nu → load the module → read the store → --set`: a second
   process, ~47ms, and a glue script in the bar's config. v2 goes `hook → --set`,
   ~6.5ms, because dispatch already runs inside the agent with the store in hand.
   **v1's `render/cache.nu` disappears too** — it existed to answer "has the model
   changed?", which is what the gate answers with nothing stored. The gate bites
   harder here than for zellij: a counter shows only a NUMBER, so a new message, a
   rename and a directory change all project identically and never reach the bar.
   `~/.config/sketchybar` keeps ONE line, which creates the pool and a hidden 30s
   item that prunes then repaints — the backstop and the janitor in one.
5b. **Bar drawers** — deferred to step 6. The rows a counter opens are the same
   rows the picker lists, so they are built once, on the shared view, and used by
   both.
6. **Picker + jump** — the terminal surface and the actions, on the shared `view/`.
7. **Cutover** — ⏳ **v1 dismissed early, on purpose** (2026-09-12). v1's hooks are
   out of `settings.json`, its bar block is out of `sketchybarrc` (one line in its
   place), `CLAUDE.md`'s session-naming rule now calls `agent-notify2 name`, and
   both surfaces are on in `~/.config/agent-notify/config.yaml`. **`ai/agent-notify/`
   is still on disk and still complete** — nothing invokes it, so reverting is one
   settings file away. Alt-a still points at v1's picker and will until step 6.
   Knowingly given up in the meantime: the picker and jump, tab glyphs, the bar
   drawers and hover previews.
   The cutover paid for itself in the first ten minutes by exposing three defects
   no test had reason to look for:
   - **A CLI write skipped the dispatch seam.** `store patch|set|drop` wrote
     straight at the store, so an agent reporting through the PUBLIC API (P5) would
     update the store and never appear on any surface. `event.nu` gained a `set`
     op and all three now go through it.
   - **`apply` could not know what had VANISHED.** A pane nobody projects onto is a
     pane nobody touches, so an agent that ended left its glyph on its pane
     forever. Dispatch already computes the previous projection for the gate, so it
     is handed to `apply` too — which also lets a surface skip the panes that did
     not move (~11ms each, and with several agents open most of them do not).
   - **`undo-rename-pane` POPS ONE RENAME off a stack**; it does not clear our name.
     After a session's worth of state changes it leaves the second-to-last agent
     title sitting there. A released pane now gets its `base` — the same title with
     the glyph removed, which is what v1 did and why v1 was right.
   And one conflation, which wrote a title onto the wrong pane before it was
   caught: **"whose event is this" and "whose environment is this" are different
   questions.** They are the same agent for a hook, which is how it hid; they are
   not for a command typed about some other agent. `core/dispatch.nu` now answers
   both separately.

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

**A module reached by two import paths is PARSED TWICE.** There is no cache
across `use` paths, and the cost is worse than additive. Measured: `store.nu`
alone +1.32ms, `zellij.nu` (which imports it) alone +2.25ms, both together
+4.51ms where a re-parse alone predicts +3.57ms. Keep the import cone a tree:
the fix was to stop a surface importing the store at all, which took the whole
dispatch cone from +5.28ms to +3.87ms per event.

**Private Use Area glyphs do not survive ordinary tooling.** Nerd Font icons
written as literal characters arrived in the file as empty strings — silently,
with no error anywhere. Write them as `"\u{f021}"`. The tests caught it only
because they asserted a title's exact contents.

**A LAUNCHD JOB'S PATH IS SMALLER THAN A HOOK'S**, which is smaller than your
shell's: the clock runs with `/usr/bin:/bin` and nothing else, so `^sketchybar`
and `^zellij` silently did nothing there — the clock pruned correctly and never
painted, while dispatch reported "applied". Every external program a surface
calls is now resolved to an ABSOLUTE path in `settings`, where a missing one is a
loud error instead of a surface that paints nothing. The same rule already
applied to `nu` itself in the wiring blocks; it applies to everything.

**`job spawn` runs a thread INSIDE the process.** It dies when that process
exits, and so does any external command it started — both verified. Nothing a
hook spawns can outlive the hook, so nothing spawned can be a clock.

**The builtin-shadowing rule bit a FOURTH time**, and this one was the most
remote: `tests/mod.nu` exported `def all`, which silently broke `| all { … }`
inside `tests/clock.nu` — a file that never mentions the name and was written
weeks later. The runner is `export def main` now, so it is spelled `tests` and
can poison nothing. When a library command wants a builtin's name, the answer is
always the same: pick another name, or make it multi-word.

**Some names are PARSER KEYWORDS and cannot be commands at all** — `run` among
them. A louder failure than builtin shadowing (it names the rule and refuses to
parse) but the same lesson: check the name before building on it. `dispatch
project`, not `dispatch run`.

**A def annotated `-> nothing` cannot END in `error make`**, because `error` is
not `nothing`. Drop the return type on commands whose job is to fail.

**A comment may not sit between an `@attribute` and its `def`.** "Attributes must
be followed by a definition" — put the prose above the attributes.

**An operator cannot start a continuation line, and a boolean expression does not
continue across lines at all.** A leading `and` is read as a command (`Command
'and' not found`); moving it to the end of the previous line gives "incomplete
math expression" instead. Bind the halves with `let` and compare them on one line.

**A flag cannot start a continuation line.** `summarise (…)\n  --title "x"` is a
parse error; bind the argument to a `let` and keep the call on one line.

**`ls` on a glob that matches nothing is an ERROR**, not an empty list — and a
directory that outlives its contents is the ordinary case for a store whose last
agent has just ended. `try { ls … } catch { [] }`, or the first empty store takes
every surface down with it.

**`reject` errors on a missing column**; `reject --optional` does not.

**Intermediate pipelines print nothing under `nu -c`** — only the final one — so
anything a script means to show needs an explicit `print`.
