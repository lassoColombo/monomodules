# agent-notify — design lock

A ground-up rebuild of `ai/agent-notify`, developed alongside the original and
promoted over it when finished — which it now is: the original is deleted and
this module carries its name (D17). This file is the contract: the principles it
was built to, the measurements those principles were tested against, the
decisions taken, and — just as importantly — the options considered and
rejected, so none of them get re-litigated by accident.

Status markers used throughout:

- **LOCKED** — decided. Do not reopen without new evidence.
- **PROPOSED** — recommended from measured data, awaiting explicit sign-off.
- **OPEN** — genuinely undecided.
- **REVISED** — was right about the problem, wrong about the answer. The row
  says which half survived.
- **SUPERSEDED** — overtaken by a later decision, which the row names. Kept
  because a decision that quietly disappears gets made again.

---

## 1. Principles

**P1. Everything lives in the module.** All logic, all graphics, for every tool
— zellij, SketchyBar, Claude Code, and any tool added later. Nothing of
substance may live in `~/.config/sketchybar/plugins/*.sh`, in `sketchybarrc`, or
in a shell glue script. The bar's config gets exactly one line: a call into the
module.

**P2. All logic is written in nushell.** No bash, no other language, anywhere in
the module. This is a hard constraint and it was tested before being accepted —
see §2.

**P3. It must be efficient and fast to load.** Performance is a first-class
concern, discussed explicitly and measured rather than assumed. Every decision
in §4 that trades one cost against another cites a number from §3.

**P4. The on-disk session-store is the core.** Everything else is a projection
of it. The session-store must offer (a) powerful and precise ways to write it,
and (b) submodules that integrate other tools onto it — zellij, SketchyBar,
and others — as **opt-in** integrations.

**P5. Agent-agnostic.** This is not a Claude Code tool. *Every* agent must be
able to call the entry points — another CLI agent, a script, a cron job,
something not yet written. Claude is one agent among N, and its payload adapter
is a convenience, not the path. Three things follow, and they are design
constraints rather than aspirations:

- **The write API is a public interface, not an admin convenience.** A foreign
  agent talks to us by running a command, so the session-store's command set
  needs typed flags *and* a JSON body on stdin — the lingua franca for an agent
  written in bash or python — with clear errors and machine-readable output.
- **Identifiers are opaque.** The core may not assume a UUID or any other shape.
- **The state vocabulary is the one thing the core must close** (§4.1).
  Everything else opens up; states cannot, because displays render them. A
  shared vocabulary is what an adapter adapts *to* — it is the mechanism that
  makes P5 work, not a limit on it.

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

At that worst-ever burst an all-nushell hot path costs ~90ms of CPU — **9% of
one core, for one second, three times in three weeks**. The bash gate's saving
in that same second is 2.3% of a core. It was optimising a non-problem.

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
| leaf `lib/session-store.nu` (1.9KB) | +0.30 |
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
>    stays filter — the modularization preference and performance do not conflict.
> 4. **`use` is parse-time.** Nushell: *"module files and their paths must be
>    available before your script is run as parsing occurs before anything is
>    evaluated."* There is no runtime import. This single fact shapes §4.4.

### Store I/O — negligible

| | ms |
|---|---|
| `session-store get` (one record) | 0.08 |
| `open --raw \| from json` | 0.06 |
| `session-store put` (atomic: save + mv) | 0.26 |
| `to json` (one record) | 0.04 |
| `session-store list` | 0.39 (1 rec) → 3.48 (50 recs), ~0.065/record |

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
writer, **47.5ms is avoidable subprocess work**: `list-panes` 11.5 +
`rename-pane` 11 + pandoc 25.

### v2 projection

| | ms | |
|---|---|---|
| `PostToolUse` re-assert, `changed: false` | **21.3** | measured, step 2 |
| `Stop` — a real state transition | **22.2** | measured, step 2 |
| an event we do not subscribe to | 20.9 | measured, step 2 |
| + a pane rename, once zellij lands | ~33 | projected (11ms per zellij call) |

Against v1: **2.6× cheaper** on a state change (58.7ms), **3.9×** when v1 pays
for pandoc (86.8ms), and that is before counting the second nu process v1 spawns
to repaint (+34.6ms) which v2 does not have.

The honest other side: for the COMMON event — a redundant `PostToolUse` — v1's
bash gate costs 3.9ms and v2 costs 21.3ms. That is the price of P2, and it is
the trade §2 measured before accepting: at the worst burst ever observed (6 in
one second) it is 13% of one core for one second, and at the real rate it is
37ms of extra CPU per agent per minute — 0.06% of a core.

> Measured under load, with the floor drifted to ~14.6ms from the 12.86ms of §3
> (this machine was busy running the suites). On a quiet machine subtract ~2ms.

> Revised after step 1, upward and honestly. The original projection assumed a
> ~3ms hot cone; the session-store alone measures **+1.76ms** of parse, so a realistic
> full cone (core + view + dispatch + two integration hot halves) is 4–6ms rather
> than 3. The conclusion is unaffected — v1's single `use ai` costs +19.4ms — but
> the budget is tighter than first claimed, and every later step should watch it.

---

## 4. Architecture

### 4.1 The session-store is the core — and it holds facts, not decisions

```
$XDG_DATA_HOME/agent-notify/
  sessions/<id>.json        one file per session
```

One namespace. One file per session, so concurrent agents never contend; writes
are temp+rename, so a reader never sees half a record. (Both inherited from v1,
which got this right.)

**Records hold facts. Display decisions are derived at read time.** v1 bakes a
decision into storage — an eight-line ladder picks *which* base name wins,
freezes it into `pane_name`, and guards it with `pane_locked`. v2 stores both
facts (`name`, what the agent called itself, write-once; `name_auto`, the cwd
basename, last-wins) and resolves precedence in the view. Derivation costs
0.04ms, so there is no reason to bake a decision into storage where a later
change of mind would need a migration to undo.

**The session-schema is open, with a small core and one namespace per owner.** A
closed session-schema would make the core depend on every integration's fields —
adding an integration would mean editing core — which contradicts P4's opt-in
requirement. So the core guarantees a handful of fields and owns their policy;
everything else belongs to a namespace named after its owner, integration or
agent alike.

```nu
{ # ── core-owned ──────────────────────────────────────────────────────────
  id: "6923c0bc-…"        # caller-supplied, opaque, unique per agent instance
  agent: "claude"        # who is reporting
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
so its session-store cannot exist without zellij — incompatible with zellij
being opt-in. The key is the reporting agent's own session id, whatever shape
that takes (P5).

Because the id is opaque, the **filename derivation must be injective**:
anything outside `[A-Za-z0-9._-]` is percent-encoded, so the common case stays
greppable and no two ids can collide onto one file. (v1's `str replace '/' '_'`
collides `a/b` with `a_b`.) The record carries its own `id`, so a filename never
needs decoding.

**One guarantee the pane key gave us for free is now merely a fact:** "one pane,
one agent" can be violated — a crashed session's stale record and a fresh one
can both claim pane 3. The core does not resolve this, because the core must not
know what a pane is; the zellij projection picks the live record and the
session-store-garbage-collector drops the dead one.

### 4.2 Writing — `patch` and the `changed` flag

```nu
session-store get   <id>                → record | null
session-store patch <id> <changes>      → {changed, before, after}
session-store set   <id> <record>       → replace wholesale
session-store end   <id>
session-store list  [--where <closure>] → all records
```

**`patch` returning `changed` is the load-bearing decision of the whole
design.** It performs the read-merge-write atomically, enforces field policy,
and reports whether the world actually moved — comparing the *comparable*
fields only, ignoring the stamps it sets itself.

That one boolean replaces three separate mechanisms in v1 — the bash fast-path
gate, the `working` verb's early return, and the render-side model cache — with
a single check in the one place able to answer it. When it comes back false the
event ends: no zellij, no sketchybar, ~15ms, nothing touched.

Field policy is the only cleverness the session-store gets, and it is a handful
of lines: the session-schema names write-once fields, `patch` drops writes to a
field already set, and it stamps `state_since` only when `state` genuinely
changes.

### 4.3 Reading — one contract, per integration

```nu
render-items [records: list<record>]   # paint what changed. Never reads it.
```

The core reads the session-store **once** and hands the same snapshot to every
enabled integration — not for the 0.39ms, but because it guarantees every
display paints the same instant. An integration that never reads the
session-store is also trivially testable: call `render-items` with a
hand-written list, no agent, no hook, no zellij.

Ordering rules:

1. **Persist first, project after.** A projection failure must never lose a
   fact.
2. **Each integration is wrapped in `try`** — a dead zellij cannot stop the bar.
3. **`patch` does not dispatch.** Otherwise `core/session-store.nu` would depend
   on the integrations and stop being a cheap leaf that anything can import. The
   *entry point* sequences patch-then-dispatch, so a CLI write projects exactly
   like a hook does and the displays can never diverge from the session-store.

### 4.4 Hot and cold — the layout consequence of parse-time `use`

Because the hot entry pays for everything it imports, every integration splits
into a hot half and a cold half **at file boundaries**, by one question: *does
an event need this?*

```
agent-notify/
  mod.nu                    facade — re-exports the public commands
  hot.nu                    THE event entry. Narrow cone, nothing cold reachable.
  cli.nu             COLD   human/admin command set
  core/
    session-schema.nu       record shape, states, field policy, version
    paths.nu                XDG paths
    session-store.nu        get/patch/set/end/list — pure state, no I/O beyond it
    config.nu               read/normalize/validate the YAML (strict)
    dispatch.nu             fan out to enabled integrations
    session-store-garbage-collector.nu
                     COLD   liveness + reconciliation (the 30s timer)
  view/                     presentation-neutral derivation shared by all displays
  agents/
    claude.nu               hook payload → session-store changes
  integrations/
    zellij/
      render.nu      HOT    titles
      admin.nu       COLD   liveness source, jump, install
    sketchybar/
      render.nu      HOT    model → one message
      items.nu       HOT    pure model→args builders
      theme.nu       HOT    palette/geometry, defaults overridable from config
      install.nu     COLD   item pool, click/hover help-setup, teardown
    picker/          COLD   the terminal drawer (`browse`)
```

Hot cone budget: **4–6ms**, of which the session-store already spends 1.76
(measured in step 1). Every KB of cold code kept out of it is 0.26ms — so the
split has a number behind it, not just taste — and comments are ~9× cheaper than
code, so the documentation is not what costs.

**Opt-in is about behaviour, not parse cost.** `use` being parse-time means the
hot entry imports every integration's hot half unconditionally; config gates the
*calls*. A disabled integration touches nothing and may be absent from the
machine entirely, but it still costs its ~1ms of parse. Making that zero would
require a generated entry point, which we are not doing unless numbers ever
demand it.

### 4.5 Configuration

**`$XDG_CONFIG_HOME/agent-notify/config.yaml`** — data, read at runtime.

Resolution order: `$env.AGENT_NOTIFY_CONFIG` (path override, for tests and for
running v2 beside v1) → the XDG path → built-in defaults. An absent file is a
clean fallback, because `open` is a runtime read.

This deliberately departs from the house convention (`$env.gg_config`,
`$env.kubebridge_config`, `$env.ai_config`) for a principled reason worth
recording in the module header: those modules are typed at a prompt by a human
in a configured shell. agent-notify is invoked by Claude Code, by sketchybar, by
zellij — processes with no shell config, and `nu -n` cannot see `$env` set in
`config.nu`. A `source`-based bridge would work but is parse-time: a missing
file becomes a parse failure, and the path cannot be chosen at runtime. `open`
has neither problem and costs 0.06ms.

**What stays in `config.nu`: nothing.** This was written expecting the v1
arrangement to survive — `$env.ai_config.picker` (skim) and `.render` (bat),
closures wired in by `module-hooks.nu`. Both are gone (D48, D54): the picker has
no engine to swap and nothing to render, so there is no code in the env and no
hook to wire. Data in the file, and only the file.

Colours live in the config file. Validation is **strict**: an unknown
integration name or a malformed entry is an error with a helpful message, not a
silent no-op, because a hand-edited file makes typos likelier than an env record
does. A `config show` command prints the resolved record and the file it came
from.

### 4.6 Agents — one file per agent

The agents that might report into the session-store agree on almost nothing.
Surveyed before committing to a shape:

| agent | help-setup | payload transport | event named by | current-session | reply contract | states reachable |
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
current-session**, **the reply contract**, and **how much of our state
vocabulary the agent can even reach**. A declarative mapping table could encode
the first three. It cannot encode the fourth (Gemini must print `{}` where
Claude must print nothing), and it cannot encode Aider, which supplies no
current-session at all and needs its module to invent one. Encoding all of it
would have produced a worse nushell.

So: **one file per agent**, exposing three things.

```nu
export const INFO = {name, title, transport, states}  # for `agent-notify agents`
export def to-operation [event: string, payload: record] -> operation
                                                      # PURE — the thinking
export def main [...]                                 # the entry; the peculiar parts
```

`to-operation` is a pure function, which is why 30 of Claude's 37 assertions
need no session-store, no hook and no agent. `main` owns transport, reply and
exit code — the parts that are strange per agent, expressed where strange is
cheap.

**Nothing registers an agent.** The agent's own configuration names the file
directly, so an agent module works the moment it exists. `agents/mod.nu` lists
the integration-registry ones for `agent-notify agents` and for nothing else;
an entry point imports exactly the one agent it is for and pays to parse no
other.

**A half-wired agent is worse than an unwired one.** Codex integration-registry
here as a `notify` module first, and `notify` fires once, when a turn ends. That
reached one of the four states, so a Codex record read `awaiting` from its first
turn to its last — true only where it happened to coincide with reality, and
wrong every second the agent was working. Nothing was malformed: a legal state,
a legal agent name, validation passing. The session-store has no way to say *I don't
know*, so a one-sided hook writes a confident fact that outlives its truth, and
the counter a display exists to show — "2 agents waiting for you" — stops being
worth a glance. The order of preference when an agent under-reports:

1. **Fix the transport.** If a state is reachable at all, carry the fact rather
   than a guess about it. Codex's hooks reach all four, which is what the module
   uses now.
2. **Let the display read `INFO.states`.** Every record names its `agent`, so a
   display can join to that agent's declared reach and decline to count what it
   cannot know. This is what makes the field load-bearing rather than
   decorative, and it is the only answer for an agent like Aider that supplies
   nothing.
3. **Decay from `state_since`.** Catches the opposite failure — an agent stuck
   in `working` because its end-of-turn hook never fired. Useless for this one:
   `awaiting` is a resting state, so age says nothing against it.

**One transport per agent**, even when the agent offers several. Codex has both
`notify` and hooks, and they identify an agent differently — `thread-id` against
`session_id`, with nothing establishing that those are the same value. Running
both would risk two records for one agent: the same pane counted as working and
awaiting at once. An agent module takes the transport that reaches the most states and
ignores the rest.

**Setup help is printed, not applied.** `agent-notify agents help-setup codex`
prints the block to paste. Merging into four foreign configs in three formats —
with backups, pre-existing entries and an uninstall path — is a great deal of
blast radius for the convenience of not pasting a block yourself.

### 4.6b Liveness — proving an agent is gone

Records are dropped by `SessionEnd`, so the only leaks come from agents that
never got to say goodbye: a killed process, a crash, a closed pane, a closed
terminal.

**An agent is a process.** If its process is gone, the agent is gone. Every
other signal is a proxy, and every proxy is wrong somewhere:

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
climb until we meet the name **the agent declares** — `process: "claude"` in
`agents/claude.nu`, which is where agent-specific knowledge already lives.
`$env.AGENT_NOTIFY_PID` short-circuits the walk, the same escape hatch
`AGENT_NOTIFY_ID` gives for current-session (P5).

Stored as `proc: {pid, started}` at `SessionStart` — where it can be new — and
looked up again on `UserPromptSubmit`, once per turn. **That retry is what stops
a missing pid being permanent**: if the walk fails once, or the session predates
this code, that agent could otherwise never be proved dead for the rest of its
life and every display would show it forever. No session-store read is needed to
decide whether it is missing, because attaching it is idempotent — a pid does
not change within a session, so a second attach produces an identical record,
`changed` is false, and nothing is written or painted. Measured:
`UserPromptSubmit` 28.5ms → 40.2ms, once per turn; `PostToolUse`, which fires
hundreds of times, is untouched at 29ms. The start time is not decoration: pids
are recycled, so a number alone would eventually match a stranger's process and
keep a dead agent alive forever. A number *and* the second it started cannot be
confused.

The check is one `ps` for every recorded pid at once. Present with a matching
start time → alive. Absent → **proof** → drop.

**The safety rail: we cannot tell → we drop nothing.** That covers a record with
no `proc` (its SessionStart predates this, or its agent could not be located)
and a `ps` that failed to answer. One unreadable answer must never wipe a live
session-store.

**One extra case.** `/clear` does not end the process — the same agent starts a
fresh session inside it, so two records can name one genuinely live pid. A
process runs one session at a time, so among records sharing a live pid only the
most recently updated survives.

Never on a hook: `ps` costs ~13ms and a hook could do nothing with the answer.
It runs from `session-store sweep`, from `displays refresh`, and later from the
picker.

**The sweep hands its casualties to the repaint.** `sweep-dead-sessions`
returns the WHOLE records it removed, and `displays refresh` passes them to
dispatch as `--gone`, which folds them into "what the session-store looked like
a moment ago". Without that, `--force` meant "pretend
nothing was there before" and a display could not tell what had disappeared: an
agent killed in a pane that OUTLIVED it kept its title for good. SketchyBar
never noticed the bug — a counter is recomputed whole every time — which is
exactly why it had to be found on zellij.

What it deliberately cannot do: a **hung** agent stays, which is correct — it
really is still there. And an agent whose `SessionStart` we missed has no `proc`
and can never be pruned.

### 4.6c The prune-daemon — who looks when nobody reports

The session-store is **pushed, never polled**: an agent's hook writes it and
paints the displays in the same breath, which is why a repaint costs 6.5ms and
needs no daemon. But a dead agent fires no hook — that is what dead means — so
its record is never revisited and every display keeps showing it.

So something has to look. **The daemon is not a second pruning mechanism**: it
runs exactly the same pid-based `sweep-dead-sessions`, then repaints. All it
contributes is the looking.

Three candidates were tried, in this order:

| prune-daemon | why not |
|---|---|
| a hidden SketchyBar item, `update_freq=30` | worked, and free — the daemon is already running. But it made a core guarantee depend on one OPTIONAL display being installed and enabled |
| `job spawn` | a nushell job is a thread inside its process: it dies when that process exits, and so does anything it starts (both verified). A hook lives ~30ms |
| **a launcher the machine already runs** | ✅ it *is* the periodic thing. No daemon to keep alive, no lock file, no pid to supervise, no detaching trick — and it survives logout and reboot, which a spawned process would not |

The tick is `displays refresh` — the same command a human types. Verified end to
end: a record planted with a dead pid was gone in 15 seconds.

**And `job spawn` is not a near miss, it is a closed door.** Re-checked on
0.115.1: nushell has no `disown`, all jobs are threads that die with the shell,
and "spawn an independent background process" is still an open design question
upstream ([#15200](https://github.com/nushell/nushell/issues/15200),
[#15201](https://github.com/nushell/nushell/issues/15201)) — hard cross-platform
because Windows has no `fork`. The community answer is to shell out to `pueue`,
which is D10 with extra steps. So there is no native-nushell periodic tick on
any platform, and delegating to the OS is not a macOS shortcut, it is the only
shape available.

#### The launchers (D66, D67)

launchd is macOS, and it was the one genuinely platform-locked thing in `core/`.
So it became a table, the same shape as `core/dispatch.nu`'s display registry
and for the same reason — nushell has no first-class modules, so a name cannot
become a module at runtime.

```
core/prune-daemon/mod.nu       the tick, the log, the registry, the refusals
core/prune-daemon/launchd.nu   macOS   — one plist, StartInterval
core/prune-daemon/systemd.nu   Linux   — a .service and a .timer, user scope
```

Each launcher answers the same five questions: `INFO`, `available` (a **probe**,
returning `{ok, why}`), `unit-files` (**PURE** — the files, written nowhere),
`register`/`unregister`, and `status` (which reads the interval back **out of
the unit file**, because the file is what the launcher obeys and what someone
typed once is only a memory of it).

**`unit-files` being pure is what makes this testable on one machine.** The
systemd timer is asserted in full by `tests/prune-daemon.nu` running on a Mac
with no systemd on it. Same split as `render-items` / `push-items`.

**Nothing autodetects (D67).** `install` takes the launcher as a required
argument with a completer; the machine is not asked. Autodetection would be
right nearly always and invisible when wrong — and wrong looks exactly like
"dead agents linger", with nothing in any log. So `available` turns from a
chooser into a **validator**, and its `why` is shown verbatim, because a refusal
is the whole of the UX for a choice the user made:

```
agent-notify: systemd cannot run here — systemctl is not on PATH (this machine is macos)
```

**The asymmetry is deliberate: you name a launcher to CREATE one, never to ask
about one or to destroy one.** `status` reports every launcher — so "is it
running?" is answerable without remembering what you installed six months ago,
and a unit file that arrived with someone's dotfiles is visible rather than
immortal. `uninstall` sweeps them all, so a launcher can never be left armed
because detection would now answer differently. That drift-proofing is why there
is no state file recording what was installed.

Two refusals fire before anything touches the disk: a launcher that cannot run
here, and a second launcher already loaded (harmless — a sweep and a repaint are
both idempotent — but never what anyone meant).

**What a launcher may touch: only files it named, only units it created.** One
plist; one `.service` and one `.timer`, both named after us, both under
`~/.config/systemd/user/`. Never `user.conf`, never `system.conf`, never
`DefaultTimerAccuracySec=`, never a unit it did not create — and `uninstall`
leaves nothing behind. Same spirit as the rule that nothing of ours lives in
anyone else's config directory: a unit we own and can fully remove is ours;
another tool's config file is not.

Windows was scoped out on purpose. Task Scheduler has a hard one-minute floor
and would need `/XML` to survive the quoting, but the real reason is that
Windows has neither zellij nor SketchyBar — the clock would tick correctly and
paint nothing.

### 4.7 Displays — describe, decide, write

```nu
export const INFO = {name, title}
export def settings [given: record] -> record     # config only: defaults, strict
export def discover-own-location [stored, settings] -> record
                                                  # OPTIONAL: what this process
                                                  # sees of ITSELF
export def render-items [records, settings] -> record
                                                  # PURE: key → what to show
export def push-items [changed, removed, settings]
                                                  # write these, undo those
```

**A display describes. Dispatch decides. The session-store holds facts.**

`render-items` returns a MAP, not an opaque blob, and that is what makes the
division possible: dispatch holds two of them — the session-store as it was, the
session-store as it is — and diffs them itself, once, correctly, for every
display that will ever exist.

```
key changed          → changed
key gone from after  → removed, WITH its old value, because undoing needs it
both empty           → nothing to say, nothing is sent
```

The gate is no longer a separate idea; it falls out of the diff. And the diff is
**per key**: with four agents open, a state change moves one pane title and the
other three are never written. A display used to work that out for itself, and
zellij's hand-rolled version is what this replaced.

**Two snapshots, not a delta.** Callers pass the whole session-store before and
after, so there is one spelling for "what was there a moment ago" whether the
change came from a hook (one record moved, `core/operation.nu` reconstructs the
rest) or from the prune-daemon (some records were pruned, `displays refresh`
prepends them). `--gone` and `--me` are gone with it.

**`discover-own-location` is why `render-items` can be pure.** zellij needs to
know which pane it is in, which only the running process knows. Rather than
passing ambient facts through `settings` and branching inside `render-items` —
*"is this record me?"* — `discover-own-location` reports them, dispatch records
them in the display's own namespace, and by the time `render-items` runs they
are just facts in the session-store like any other.

**A display never writes the session-store**, never learns what changed, and
never reads back what it wrote. It keeps a display a LEAF of the import tree
(§10) and keeps one writer.

The config file has **the same shape as a session-store record**: a small core
the module owns, one namespace per owner, unknown keys rejected. One idea, two
files.

```yaml
displays: [zellij, sketchybar]     # what the session-store is PUSHED to; order is dispatch order
zellij:
  binary: zellij                   # shared by both halves
  display:                         # PUSH — how it shows the session-store
    glyphs: {working: 🧠, awaiting: 🔔}
  commands: {}                     # PULL — how its commands behave
```

**A tool's namespace has two halves** (D47), because a tool can do two unrelated
things with the session-store and they are not controlled by the same switch:

| | driven by | examples | turned on by |
|---|---|---|---|
| **push** | an event arriving | pane titles, bar counters and drawers | `displays:` |
| **pull** | you running a command | the picker, the jump | nothing — you ran it |

That distinction was implicit and therefore wrong: `displays:` reads like "which
integrations exist", so putting the picker inside zellij's directory would
suggest that removing `zellij` from the list takes the picker away. It must not
— removing it means *stop renaming my panes*, and nothing else. Splitting the
halves
**in the file** makes that unambiguous without a paragraph of explanation.

Keys at a tool's own level are shared by both halves, which is what `binary`
actually is: the same program renames a pane and focuses one.

A namespace for a display that is merely switched off is fine — disabling should
not mean deleting your colours, and its commands still work. A namespace naming
a display that does not exist is an error, because that is a typo.

`config check` also runs each ENABLED tool's own `settings` over its `display`
half, because only the tool knows what a key MEANS — a misspelled colour is
exactly the failure that command exists to explain, and nesting gives a typo one
more place to hide.

**Strict where a human is, lenient where a hook is.** `config check` is exact
and loud; `load` never throws. A YAML typo must not be able to stop the
session-store recording facts. The cost is that a broken config shows up as "my
bar stopped moving" rather than as an error, which is what `config check` is
for.

**Nothing in the dispatch path may throw.** It runs after the session-store has
committed. Each display is wrapped alone, so one failing cannot stop the next.

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
| D7 | No display/render cache, no `displays/` namespace | **LOCKED** | saves ~2.4ms in a rare case; costs a namespace, a staleness class, and a concurrency race |
| D8 | One session-store namespace: `sessions/`, one file per session, temp+rename | **LOCKED** | inherited from v1, measured cheap (0.26ms put) |
| D9 | In-process dispatch — no poke, no `render.sh`, no second process | **LOCKED** | step 3 — built and running: `core/dispatch.nu` fans out inside the agent's own process. It removed a whole nu spawn + parse (34.6ms/event measured) and two glue scripts with it |
| D10 | No daemon | **LOCKED** | held all the way through: at ~1 event/s, saving the 12.9ms floor never justified the lifecycle risk, and the one periodic job that IS needed is a launchd `StartInterval` (D39), not a process we keep alive |
| D11 | Identity = the agent's session id, opaque and caller-supplied | **LOCKED** | the only way zellij can genuinely be opt-in; opaque because of P5 |
| D11b | Agent-agnostic: any agent may call the entry points; Claude is one agent among N | **LOCKED** | P5 |
| D11c | Open session-schema — small core + one namespace per owner | **LOCKED** | a closed session-schema would make core depend on every integration |
| D11d | Closed, core-owned state vocabulary | **LOCKED** | displays cannot render a state they have never heard of |
| D11e | Injective id → filename encoding (percent-encode outside `[A-Za-z0-9._-]`) | **LOCKED** | opaque ids may contain anything; v1's mapping collides |
| D12 | Facts not decisions: the session-store holds `name` or nothing | **REVISED** (step 4) | right about the problem, wrong about the answer. `name_auto` was never built and is not wanted: a name the agent did not choose is not a fact, so the session-store holds one field and each display computes its own fallback at paint time (`name` → `cwd` basename → id prefix). v1's base-name ladder and `pane_locked` are gone either way |
| D13 | Lazy zellij reads via `title_written` and `context_read_at` | **SUPERSEDED** by D23/D40 | never built, and it turned out not to be needed. The projection gate skips the write when nothing moved, and dispatch's per-key diff skips the ones that did not — with no extra fields, no throttle and no staleness to reason about. `discover-own-location` covers the tab read (D43). Two state fields avoided, not optimised |
| D14 | Store the message as written; derive the flattened form at paint time | **LOCKED** | step 5b — built: `integrations/sketchybar/text.nu` flattens at paint, the session-store keeps the markdown. It is what let the picker later take a different view of the same field, and then stop needing it at all (D57) |
| D18 | One FILE per agent, not a declarative mapping table | **LOCKED** | §4.6 — transport, reply contract and current-session all vary; a map would become a worse nushell |
| D19 | Agents are discovered by the agent's own config naming the file; no registry | **LOCKED** | adding an agent is one new file |
| D20 | Setup help is printed, never applied | **LOCKED** | four foreign configs in three formats |
| D21 | An agent module uses ONE transport, even when its agent offers several | **LOCKED** | §4.6 — Codex's `notify` and hooks key on different ids; running both double-counts one agent |
| D22 | Fix an agent's transport before inferring states it does not report | **LOCKED** | §4.6 — the session-store must not hold a confident fact nothing supports |
| D23 | The projection gate: compare `render-items(before)` with `render-items(after)` | **LOCKED** | §4.7 — replaces v1's bash gate, trigger dedup and session-store-garbage-collector with one comparison, and no state |
| D24 | Strict config validation in the CLI, never in the hook | **LOCKED** | §4.7 — a YAML typo must not be able to stop the session-store recording facts |
| D25 | The readers are `displays/`, the writers are `agents/` (then `clients/`) | **REVISED** (step 6, and again by D65) | half right. The writers are still `agents/`; the readers went back to `integrations/`, because an integration has two halves and only one of them is a display — see D47 |
| D26 | Displays reach dispatch as a hand-written table of closures | **LOCKED** | `use` is parse-time; it is also what makes them testable with nothing installed |
| D27 | A display reports what it learned; dispatch writes it | **LOCKED** | §4.7 — one writer, and it keeps displays out of the session-store's import cone |
| D28 | A pane's name comes from the session-store, never from parsing its old title | **LOCKED** | user decision; deletes ~60 lines of v1 and one zellij call per event. A manual rename is overwritten |
| D29 | The import cone must be a TREE | **LOCKED** | §10 — a diamond is parsed twice, on every event, forever |
| D30 | Liveness is the agent's PROCESS, recorded once at SessionStart | **LOCKED** | §4.6b — the only signal that is proof rather than a proxy; replaces v1's zellij scan and session-store-garbage-collector outright |
| D31 | Cannot tell ⇒ delete nothing | **LOCKED** | §4.6b — one unreadable `ps` must never wipe a live session-store |
| D32 | The agent declares how to find its own process | **LOCKED** | §4.6b — same rule as every other agent-specific fact (D18) |
| D33 | The hook paints the bar itself; no trigger, no daemon round trip | **LOCKED** | step 5 — dispatch already holds the session-store; v1's path cost a second nu (~47ms) and a glue script |
| D34 | A side effect is built as DATA first (`message`), then sent | **LOCKED** | step 5 — it is what lets the bar be tested exactly, with no bar installed and no subprocess |
| D35 | A fixed item pool, created once, never added to or removed from | **INHERITED** | v1's most expensive lesson; re-measured at 17.51ms per add+remove against 6.5ms per message |
| D36 | Every write goes through `core/operation.nu`, the CLI included | **LOCKED** | step 7 — the command set IS the public API (P5); a write that skips the seam is a display that never hears about it |
| D37 | `push-items` receives the previous projection | **LOCKED** | step 7 — the only way a display can act on what has disappeared, and it makes "skip what did not move" free |
| D38 | Dispatch answers "whose event" and "whose environment" separately | **LOCKED** | step 7 — identical for a hook, different for a CLI write about another agent |
| D39 | The prune-daemon is its own job under a launcher, never a display's item | **LOCKED** | §4.6c — a core guarantee must not depend on an optional display being installed. Which launcher became a table in D66; the rule that it is never the bar's `update_freq` is unchanged |
| D40 | `render-items` returns a MAP; dispatch owns the diff | **LOCKED** | §4.7 — one correct implementation instead of one per display, and the gate falls out of it |
| D41 | Dispatch takes two session-store SNAPSHOTS, not a delta | **LOCKED** | §4.7 — one spelling for "a moment ago", whether a hook or the prune-daemon is calling |
| D42 | `discover-own-location` reports the environment; it is not smuggled through `settings` or `push-items` | **LOCKED** | §4.7 — it is what lets `render-items` be a plain function of records |
| D43 | A tab's name is learned ONCE, in the read we already need for its id | **LOCKED** | step 4b — a third subprocess per state change to respect later renames was not worth it |
| D44 | A hover's answer is BAKED into the item at paint time, as a shell command | **LOCKED** | step 5b — the paint already knows the text; the alternative is a second nu per hover, which is the thing v2 deleted |
| D45 | A preview's text is made single-quote-safe (`'` → `’`) rather than shell-escaped | **LOCKED** | step 5b — probed: inside single quotes `$HOME` and backticks are already literal, so one substitution is the whole of the escaping |
| D46 | The bar's slots are keys in the projection, one per row | **LOCKED** | step 5b — D40 then does the per-slot diffing for free; v1 needed a disk cache and ~60 lines of its own |
| D47 | A tool's config has two halves, `display` (push) and `commands` (pull) | **LOCKED** | §4.7 — `displays:` must not read as "which integrations exist"; splitting it in the FILE is what stops removing a display from taking its picker away |
| D48 | The picker has NO configurable engine — skim is a dependency | **SUPERSEDED** by D54–D57 | half right: the hook goes, but so does skim. There is no engine and no dependency at all — nushell's own `input listen` and zellij's `dump-screen`, nothing else |
| D49 | `displays/` → `integrations/`, one directory per tool, one file per half | **LOCKED** | step 6 — the halves must be separate FILES: the push half is in every hook's import cone and the pull half must never be |
| D50 | The jump names NO window manager and assumes no OS | **LOCKED** | step 6 — raising the terminal's window is only needed by a BAR CLICK; the picker runs inside the terminal, where it is already in front. Deferred with the click |
| D51 | `jump argv` is the whole decision; `main` only runs it | **LOCKED** | step 6 — the same data-first split as `commands`/`push-items`, and here it is what lets the cross-session branch be tested at all: running it moves a real screen |
| D52 | `browse` runs IN PLACE; the floating pane belongs to the keybinding | **LOCKED** | step 6 — v1 re-launched itself through `zellij run --floating` and needed a `--here` flag to not. Same bargain as `sketchybarrc` and `settings.json`: we print the block, you own the file |
| D53 | `browse` does not prune | **LOCKED** | step 6 — the prune-daemon already does, every 30s. A second mechanism for one guarantee, and all it saves is a jump that says "no session called 'x'" |
| D54 | The picker OWNS ITS EVENT LOOP — `input listen`, not `input list` | **LOCKED** | step 6b — `input list` is OPAQUE: it blocks and reports nothing until enter, so nothing can redraw a preview beside it. Every design that kept it needed a second process parsing the highlight back off the picker's own screen |
| D55 | The picker is `picker/`, its command is `cli/browse.nu`, and each integration answers a LOCATOR contract — three questions since D58, four before it | **LOCKED** | step 6b — what varies per multiplexer is where an agent lives and how to go there, and nothing else does. `screen` was the fourth and left with the pane preview (D58). tmux is one `locate.nu` and one row in `picker/locators.nu` |
| D56 | Which locator answers is decided by the RECORD, not by the config file | **LOCKED** | step 6b — `displays:` says what the session-store is PUSHED to and nothing else (D47), so switching the zellij display off must not stop the picker previewing a zellij pane. It also makes a MIXED fleet work with nothing configured |
| D57 | The preview is the agent's LIVE SCREEN; the filter matches only what the row SHOWS | first half **REVERSED** by D58; second half **LOCKED** | step 6b — the filter half stands and always will: a message is kilobytes of prose, and folding it in made a two-letter query match an agent for an invisible reason, at character 4195 of something it said an hour ago. The preview half lasted until it was lived with — see D58 |
| D58 | The preview is the agent's STORED MESSAGE, rendered the way the bar renders it | **LOCKED** | step 8 — truer lost to readable. A dump is the bottom of a TUI mid-redraw, half a spinner and a rule cut off at both edges; the agent already wrote the answer to "which of these wants me" in a sentence. It also cost a subprocess on every heartbeat and only ever covered agents that still had a pane — the rest already fell back to exactly this. Markdown rendering comes BACK to the picker, but not as new code: `core/markdown.nu` is the bar's flattener, moved up |
| D59 | A session that ends is FILED AWAY, not deleted — `ended/`, a directory the hot path never opens | **LOCKED** | step 9 — Claude Code, zellij and tmux all treat a session as durable and *running* as a state it is in; we were the only one destroying it. Keeping ended records in `agents/` behind a flag is the textbook soft delete and would have put **36.9ms on every tool call** at a month of history (measured). A second directory costs nothing, and a restore keeps `session-schema session-fields` — the core fields — so no stale pid or pane comes back with it |
| D60 | `core/markdown.nu` PARSES — `from md --verbose`, not seven regexes | **LOCKED** | step 10 — it is a BUILT-IN, so the "why not pandoc" argument that shaped D15 does not reach it: no subprocess, and measured FASTER than the regex loop it replaced (88µs vs 392µs to parse). What the regexes could not give is what the display wanted: a heading knows its depth, a list knows its level, its order and its checkbox, and a table has real cells |
| D61 | A paragraph is REFLOWED and then WRAPPED — reverses "nothing is wrapped" | **LOCKED** | step 10 — the old rule was reasoned about markdown a person hard-wraps at 80, and that is not what an agent writes. Measured on the real session-store: a message's paragraphs are ONE SOURCE LINE EACH, the longest 435 characters, so one row per source line meant cutting every paragraph at 110 and dropping the other 325. Cost: an agent's column-aligned block that is neither fenced nor indented now reflows into prose — standard markdown, and what every other renderer does |
| D62 | The flattener says WHAT A ROW IS; each display paints it | **LOCKED** | step 10 — the two displays have nothing in common to share a coloured string with. A SketchyBar item has no ANSI and no runs: it has one `label.color`, set over the wire per paint (whether row 4 is a heading depends on what the agent wrote). The picker's frame strips escapes out of every line on purpose, because that text is agent-authored. So a row is `{k, t}` and colour is applied at the far end — in the picker, LAST, after the clip, so the strip stays a defence and the clip still measures what a reader sees |
| D63 | The preview SCROLLS, and it corrects its own offset | **LOCKED** | step 10 — `pv_top` is the message's first visible row, the preview's `top`. Keys can only ever say "further down": `markdown plain-md` is given a line budget and stops there (D61), so nothing renders a whole message just to count it, and the end is knowable only by asking for one row MORE than the pane holds and getting fewer back. So `preview of` clamps and hands the used offset back, the way `rows keep-in-view` corrects the list's `top` — which is what stops ctrl-d running up a number that then has to be undone before the view moves again. ctrl-j/k by the row, ctrl-d/u by half the pane; PROBED ON A REAL PTY first, because a terminal sends ctrl-j as LF and enter as CR, and had crossterm folded them together the binding would have cost the jump key. Clearing the filter moved to ctrl-w |
| D64 | The picker's chrome is coloured, and a line is built as PIECES | **LOCKED** | step 10 — closes §9b.2. A line is `{c, t}` pieces, measured in plain text and inked last, which is the only order that works: the width a terminal cares about is the one a reader sees, and a row's name and location are agent-authored so the strip in `clean` has to stay a defence. Two things the list could not say got a home in the bars — a fleet tally on the top, `▾ n` on the bottom when the preview is scrolled — and both are RIGHT-ALIGNED so they drop first on a narrow terminal and never move the caret. One palette gotcha worth keeping: ANSI 8 (`dark_gray`) is Rosé Pine's OVERLAY tone, what a selection is drawn *on*, so as text it is nearly the background; dim chrome is `white_dimmed`, the way cmdprompt draws its box |
| D65 | The vocabulary is **session / agent / integration**; nothing is a `client` | **LOCKED** | the rename (naming.md 34) — `client` named a role in a protocol this module does not have: there is no server, and zellij reads the store as much as Claude Code writes it, so the word drew no line. The three nouns each name their subject instead — a SESSION is a row in the store, an AGENT is the program a session runs, an INTEGRATION is a tool that shows them — and read/write is a consequence rather than a name. It also removes the ambiguity `agents/` would otherwise have: rows are sessions, so `agents/claude.nu` can only be read as the file about the Claude Code PROGRAM. Carried out as a rename plus a one-shot over the live `client` field, the same treatment the `v` field got. The store directory followed (naming.md 35): `agents/` held rows, and a row is a session |
| D66 | The launcher is a TABLE, and `unit-files` is pure | **LOCKED** | §4.6c — launchd was the one genuinely platform-locked thing in `core/`, and nushell is not. Two launchers today (`launchd`, `systemd`), each answering the same five questions, registered by hand like the display registry because a name cannot become a module at runtime. The pure half is what pays for itself immediately: the systemd `.service` and `.timer` are asserted IN FULL by `tests/prune-daemon.nu` on a Mac with no systemd on it — the same `render-items` / `push-items` split, for the same reason. Windows was scoped out on purpose: a one-minute floor in Task Scheduler, and no zellij and no SketchyBar to paint |
| D67 | The launcher is NAMED at install, never detected — with a completer | **LOCKED** | §4.6c — autodetection would be right nearly always and INVISIBLE WHEN WRONG, and wrong looks exactly like "dead agents linger", with nothing in any log. So `available` stops being a chooser and becomes a validator whose `why` is shown verbatim, the completer's `description` column carries the explanation the detection used to hide, and the asymmetry is the rule: **you name a launcher to create one, never to ask about one or destroy one**. `status` reports every launcher, `uninstall` sweeps them all — which is also why there is no state file recording what was installed, and why re-detecting differently can never leave one armed |
| D68 | systemd's `AccuracySec=` is PINNED to 1s, in our own timer | **LOCKED** | §11 — it defaults to ONE MINUTE, and the default silently makes `--interval 30` a lie: the expiry lands at a stable, host-wide position inside the window, synchronised across every local timer, so a 30s timer snaps to the shared 60s grid and ticks every 60s forever. Not jitter — steady state. Pinned so that `install launchd --interval 30` and `install systemd --interval 30` MEAN THE SAME THING; if the launchers disagree about what the number means, the abstraction is not one. Per-unit, in the `[Timer]` section of the file we write — the global knob is a different setting with a different name (`DefaultTimerAccuracySec=` in `user.conf`) and nothing here goes near it |
| D15 | Replace pandoc with a nu-native flattener | **LOCKED** (step 5b) | done: `integrations/sketchybar/text.nu` does it in nushell. 25.1ms off the event path and a dependency gone. v1 could afford pandoc because it converted where the preview was STORED, on a path already spawning processes; v2's whole paint is 6.5ms. Superseded in part by D60 — the flattener is a parser now, and still no subprocess |
| D16 | Where the bench harness lives | **OPEN** | the only open row left. ~350 lines of documented nu; §8, and §9b.3 |
| D17 | Promoted to `monomodules/agent-notify`, a module beside `ai` and the rest | **LOCKED** (2026-09-12) | step 7 — it was never `ai`-shaped: reflecting agent state on a status bar is not provider-agnostic content generation, and being a submodule is what made every hook parse the whole `ai` tree. The directory, the command, the session-store at `~/.local/share/agent-notify/` and the bar prefix `an_` all carry the one name |

---

## 6. Explicitly rejected

Recorded so they are not reinvented:

- **A bash (or any non-nu) fast path** — §2.
- **A long-lived projector daemon** — the floor it saves is 12.9ms on an event
  that happens about once a second; the failure modes (dead daemon, blocked
  writer, crash recovery) are worse than the problem.
- **The SketchyBar poke (`--trigger` → `render.sh` → a second nu)** — in-process
  dispatch does the same work 34.6ms cheaper and deletes two glue scripts and
  two custom events.
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
- **A tab's base name belongs to the user**, not to us: read it back from the
  live tab title with markers stripped, so a manual rename is honoured and the
  last agent leaving cannot erase it.
- **Glyphs distinguish states by shape alone**, because zellij titles carry no
  colour; the same shapes take the state hue on the bar.
- **A fixed SketchyBar item pool** created once, `--set`-only thereafter. v1
  attributes this to `--add`/`--remove` costing the daemon ~20ms of relayout
  each — *that figure is v1's, not ours, and is the one inherited claim to
  re-measure when we build the integration.*
- **One derivation shared by every display** (`view/`), so the bar and the
  picker cannot drift apart.
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

Every spawn case is warmed first — a cold 40MB binary measures 11.2ms where
steady state is 7.4ms — and `/usr/bin/true` is always measured as the floor
everything else sits on.

Each implementation step re-runs the harness and records its numbers against the
§3 baseline, so a regression is caught when it is introduced rather than at the
end.

Both live in the repo, and neither is part of the module — nothing in `mod.nu`
imports them, so `use agent-notify` never parses a byte of either:

```
agent-notify/bench/      use agent-notify/bench   → bench floor | parse | work | rate | v2
agent-notify/tests/      nu agent-notify/tests/session-store.nu        (no -I needed)
```

---

## 8b. Working together — what this project has settled

**Explain simply, and slowly.** Short sentences. Examples before the concept.
Plain words. Density is a bug here, not a sign of rigour — "I am not getting it"
has meant *go more concrete*, never *write more*. A diagram of five lines has
beaten three paragraphs every time.

**One step at a time, each discussed before it is built.** Propose the shape,
name which decisions are mine and which are yours, then implement. Steps that
were merged (config + dispatch) went fine; steps that were split (panes before
tabs, counters before drawers) went better.

**Measure before designing, when performance is the question.** The numbers
chose the design at least four times: parse cost chose the file layout, the
event rate chose all-nushell, `--set` batching chose the one-message paint, and
the import diamond chose the display contract.

**Prefer proof to heuristics.** Liveness went through a zellij pane check and a
heartbeat before landing on the process — because those two were proxies, and
each was wrong in a case that actually happens. *No proof, no action* is the
rule that came out of it.

**One mechanism, not three layers.** "Why do we have a separate pruning process
on the bar?" was the right question, and the answer — that there was only ever
one prune, and the bar owned a timer that should not have been its — made the
design smaller.

**Dropping a constraint beats adding machinery to preserve it.** Tab names cost
a subprocess per repaint to respect; giving that up cost one sentence and
removed a third of the work.

**Cut over early and use it.** The table in step 7 is the argument: seven
defects that 250+ tests could not have found, all within a few hours of real
use.

## 9. Steps

Each step: discuss the design → implement → verify against a stated done-when,
and re-measure. v1 kept running untouched throughout; v2 used its own
session-store dir and its own bar item names so both could be live at once. That
is why the module was `agent-notify2` until step 7 promoted it — the `2` bought
the whole rebuild the right to be wrong in public, one step at a time, with the
working thing still on the bar.

0. **Baseline** — ✅ done (§3).
1. **Core session-store** — ✅ done. `core/paths.nu` + `core/session-schema.nu` +
   `core/session-store.nu`, with the command set in `cli/session-store.nu`.
   32/32 checks pass; the hot cone parses in +1.76ms; a foreign process reports
   with `echo '{…}' | nu -c '… session-store patch <id> --stdin'` and reads back
   with `| to json`. Two things the suite caught that review had not: an id
   beginning with `.` (`../../etc/passwd` strips to `....etcpasswd`) produced a
   *hidden* file — written, readable by id, and invisible to every display; and
   naming a command `get` silently shadows the builtin for every imported module
   (§10).
2. **Claude agent + the entry point** — ✅ built and verified (37/37), not yet
   wired into `settings.json`. `agents/claude/adapt.nu` is a pure
   payload→operation mapping; `agents/claude/hook.nu` is the entry;
   `core/operation.nu` holds the sequence and the dispatch seam;
   `core/current-session.nu` answers "which agent am I"; `cli/self-report.nu` adds
   `report` and `name`. 21.3ms per event. Three findings: subagent tool calls
   carry the PARENT's session id (so they fold in for free, and `SubagentStop`
   must be ignored); `StopFailure` gives us a state v1 could not express; and
   importing the entry with `-c` rather than running it as a script saves ~9ms
   per event (§10).
2b. **The agent contract, proved on a second agent** — ✅ done.
`agents/claude.nu`
   and `agents/codex.nu`, one file each; `core/hook-input.nu` holds the two
   transports; `agent-notify agents [help-setup <name>]` lists and explains them.
   85/85 across three suites, 22.8ms per event (unchanged by the refactor). Codex
   was chosen precisely because it shares almost nothing with Claude — argv
   transport, script entry, event name inside the payload, kebab-case fields, one
   reachable state — so the contract is proved rather than assumed. (The argv
   half of that is superseded by 2c; the contract it proved is not.)
2c. **Codex moved to the hook transport** — ✅ done. `notify` reached exactly one
   state, so a Codex record read `awaiting` for its whole life — a confident fact
   that outlived its truth (§4.6). Codex's hook system turns out to be
   Claude-shaped — stdin JSON, `session_id` / `cwd` / `hook_event_name`, matcher
   groups, exit 2 to block — so the agent now subscribes to six events and reaches
   all four states, and `notify` is gone rather than kept as a fallback (D21). The
   one shape difference from Claude: the event name comes from the body rather than
   our argv, which gives a single command string for all six subscriptions and no
   way for an argument to disagree with the key it is registered under.
   103/103 across three suites, 20.7ms per event. `core/hook-input.nu` lost
   `from-args` along with its last caller — an argv agent can read its own argv in
   one line, and untested code in the core is worse than a line rewritten later.
   Written from documentation rather than observed traffic (Codex is not installed
   here), which the agent's header says plainly. The suite immediately found a
   session-store bug no display had reached yet: `list` on an *emptied* session-store errored,
   because a glob that matches nothing is an error (§10).
3. **Config + dispatch** — ✅ done. `core/config.nu` (the YAML file, strict
   `problems`, never-throwing `load`), `core/dispatch.nu` (the gate and the
   fan-out), `cli/config.nu` and `cli/displays.nu`, and the seam in
   `core/operation.nu` is live. 139/139 across four suites. **Step 3 adds 0.76ms
   of parse to every event** — the price of §4.4's "gate calls, not imports",
   which parse-time `use` leaves no way around; two realistic display modules
   (18KB, this repo's comment-heavy style) were measured separately at 2.07ms,
   so the budget holds through step 5. The hook is 25ms. `integrations/` ships
   EMPTY on purpose: the contract is exercised by `tests/fake.nu`, a complete
   display that writes a line to a file and therefore needs nothing installed —
   the same move that proved the agent contract on Codex. One consequence for
   the core: `drop` now reads the record before removing it, because a display
   cannot say whether its output changed about an agent it never saw.
4. **zellij integration** — ✅ done, panes only. `integrations/zellij/mod.nu`:
   glyph plus name, one call to zellij per state change and **none at all** when
   nothing visible changed. Two of v1's three calls per event are gone, for two
   separate reasons: the pane is known from the environment (dispatch runs
   inside the agent's process), and the NAME IS A FACT IN THE
   SESSION-SESSION-STORE rather than something parsed back out of the old title
   — which deletes v1's `parse-title`, `bare-title` and its list of legacy
   glyphs outright. The cost is that a manual pane rename is overwritten, which
   is the right trade when the session-store is the source of truth. 170/170
   across five suites; the display machinery costs 3.87ms of parse per event,
   the hook 28ms. Two findings, both in §10: a module reached by two import
   paths is parsed TWICE (fixing that one diamond saved 1.4ms per event and
   produced the leaf/report rules above), and Private Use Area glyphs do not
   survive ordinary tooling — written as literals they arrived as empty strings,
   and the suite caught it as "every state has the same title".
4b. **zellij tab aggregates** — ✅ done. A tab wears one glyph per agent living
in
   it, most urgent first, in front of its own name:

   ```
    root        one agent working
    root      one working, one waiting
   ```

   It fits the step-7b contract without new machinery: `render-items` simply emits a
   second kind of key. When the last agent leaves a tab that key DISAPPEARS, and
   `removed` already means "undo this", so the glyphs come off by themselves.

   The question that had it deferred was who owns the tab's name. The answer is
   the one already settled for panes — **the session-store does** — and what makes it
   affordable is that the name is folded into a read we already needed. The
   environment says which PANE we are in but not which TAB, so `discover-own-location` runs one
   `list-panes`; that same call returns the tab's name. Both are recorded, ONCE
   per session, and a tab title is computed from the session-store ever after.

   Rejected: reading the live tab name on every write, which is correct but costs
   a third subprocess per state change. The price paid instead is that a tab
   renamed LATER is overwritten — the same bargain as pane names (D28).

   Stripping our own glyphs happens exactly once, when a tab's name is first
   learned, rather than on every write as v1 did — a tab may already carry glyphs
   written by an agent that got there first.

   Two agents in one tab could disagree about its name, but only if it was renamed
   between them starting. Lowest id wins: arbitrary, and stable, so the title
   cannot flicker between two answers.

   Cost: `list-panes` 11ms once per session; a state change is rename-pane +
   rename-tab. 265/265 across eight suites.
4c. **Liveness** — ✅ done. `core/proc.nu` (find the agent's process, ask `ps`
   which are still running) and `core/session-store-garbage-collector.nu` (the two rules), reached by
   `agent-notify session-store sweep` and by `displays refresh`, which now prunes before
   it repaints. 198/198 across six suites.
   Two earlier proposals were **dropped** on the way, both correctly: a zellij
   pane check (a killed agent can leave its pane open, so it proves the wrong
   thing) and a heartbeat (it existed only because I had no proof and needed a
   hint — with proof available, guessing has no job). One mechanism replaced
   three layers.
   Costs: `SessionStart` 27ms → 38.6ms for the one-time walk, every other event
   unchanged, `proc.nu` free to parse, `sweep-dead-sessions` 13ms of `ps` on a cold path.
5. **SketchyBar integration** — ✅ done, the three counters.
   `integrations/sketchybar/`, 233/233 across seven suites, +0.82ms of parse
   (the whole display machinery is now +4.69ms). Measured first, because the
   numbers chose the design: `--query bar` 5.98ms, `--set` one property 6.59ms,
   **`--set` TEN properties in one message 6.54ms**, `--add` + `--remove` one
   item 17.51ms. So a message costs what a process costs and almost nothing per
   property — a whole repaint is ONE call — and v1's fixed-pool rule holds,
   since adding items is ~3× setting them. The big deletion is the paint path.
   v1 went `hook → --trigger → daemon → render.sh → a fresh nu → load the module
   → read the session-store → --set`: a second process, ~47ms, and a glue script
   in the bar's config. v2 goes `hook → --set`, ~6.5ms, because dispatch already
   runs inside the agent with the session-store in hand. **v1's
   `render/cache.nu` disappears too** — it existed to answer "has the model
   changed?", which is what the gate answers with nothing stored. The gate bites
   harder here than for zellij: a counter shows only a NUMBER, so a new message,
   a rename and a directory change all project identically and never reach the
   bar. `~/.config/sketchybar` keeps ONE line, which creates the pool and then
   paints it from the session-store.
5b. **Bar drawers and the hover preview** — ✅ done. `integrations/sketchybar/`
   (`mod.nu` the contract, `items.nu` the names and the generated shell, `text.nu`
   markdown → labels), 91 assertions in its suite, 319/319 overall.
   **The projection grew from three numbers to one key per SLOT** — `count|working`,
   `row|working|0` — so D40's diff does all of the paint optimisation: a row that
   did not move is not written, and a row whose agent is gone arrives in `removed`
   and is switched off. v1's `render/cache.nu` plus ~60 lines of hand-rolled
   per-slot comparison are replaced by nothing at all.
   **Hover was the hard part.** SketchyBar reacts to a mouse in exactly one way:
   it runs an item's `script`. v1 pointed that at `plugins/hover.sh`, which
   started a whole nushell to read the session-store and wrap the text — ~47ms for every
   row the pointer brushed past, and a file in someone else's config directory.
   The fix is that **the paint already knows the answer**, so the script IS the
   answer: a literal `sketchybar --set …` command line written onto the row when
   the row is drawn. A hover is then one `sh` and one client, ~7ms, reading
   nothing.
   Probed on the real daemon before building any of it: a `script` goes through a
   shell (`$SENDER` expands, quoting is honoured), **inside single quotes `$HOME`
   and backticks stay literal**, `--update` arrives as `SENDER=forced` (so every
   generated script guards), and `mouse.exited.global` reaches a `drawing=off`
   item (so shutting the drawers lives on an item of its own and no paint ever
   rewrites it).
   Measured after: install is 74 items in ONE message, 117ms, once per bar load;
   a one-key paint is 4.9ms and the whole projection 6.5ms.
   **The gate got weaker, on purpose.** A counter is a number, so a new message
   used to project identically and never reach the bar. It is now a row's preview,
   so a `Stop` costs one ~7ms message. `PostToolUse` — the one that fires
   constantly — still projects identically and still sends nothing.
   Markdown is stripped in nushell rather than by pandoc: v1 could afford ~30ms
   because it converted where the preview was STORED, on a path already spawning
   processes; v2's whole paint is 6.5ms, and the picker still wants the markdown.
6. **Jump** — ✅ done. First the shape changed: `displays/` became
   `integrations/` (D49) because a tool has two halves and only one of them is a
   display, and the config file grew `display:`/`commands:` to match (D47).
   `integrations/zellij/jump.nu`, 16 assertions, 350/350 overall. `program.nu`
   holds the one thing both halves share: which zellij. **It names no window
   manager and assumes no operating system** (D50). v1 raised the terminal
   through aerospace, fell back to `open -a Ghostty`, and read the attached
   session out of the WINDOW TITLE. None of that is needed here: raising a
   window matters only to a BAR CLICK, and the picker runs inside the terminal,
   where the window is already in front. Running inside zellij also turns "which
   session is asking?" into `$env.ZELLIJ_SESSION_NAME`. Probing zellij first
   paid for itself three times: it **exits 0 on failure** and puts the reason on
   stderr; it uses stderr for successes too ("already focused"); and
   **`switch-session` CREATES a session it cannot find** — a stale record would
   have spawned an empty session and gone there, which the probe demonstrated by
   leaving an orphan server behind. `jump argv <who>` is the whole decision as
   data (D51) and `main` is four lines that run it. That is what makes the
   cross-session branch testable: obeying it moves a real screen.
6b. **The picker** — ✅ done, and rebuilt from nothing. A skim + bat version
   integration-registry first and was rejected outright, both dependencies with it. The
   replacement has NO external dependency at all: nushell's own `input listen`
   and zellij's `dump-screen`, and nothing else.
   **It is not in `integrations/zellij/`** (D55). Three things vary per
   multiplexer — where an agent lives, what is on its screen, how to get there —
   and nothing else does, so those three are a four-question LOCATOR contract
   (`integrations/zellij/locate.nu`) and everything else is a plain picker in
   `picker/`, with its command in `cli/` beside the others. tmux would be one
   more `locate.nu` and one more row in `picker/locators.nu`. Which locator
   answers is asked of the RECORD, not of the config file (D56), so a mixed fleet
   works with nothing configured and switching the zellij DISPLAY off does not
   take the preview away.
   **It owns its event loop** (D54), because `input list` is opaque: it blocks
   and reports nothing until enter, so nothing can redraw a preview beside it. A
   design that kept it was built, worked, and was rejected — it needed a second
   pane parsing the highlight back off the picker's own screen, and could break
   silently. Owning the loop is resilient through three ABSENCES: nothing to
   parse (we set the selection), nothing to poll (`input listen` blocks), nothing
   to coordinate (one pane, one process).
   **The preview was the agent's real terminal** (D57), 12ms per read, truer than
   anything we could record — and step 8 reversed it (D58), because truer was not
   readable. A `--timeout 2sec` heartbeat keeps the frame live while you sit
   still, which is still what it is for.
   Four calls in `picker/mod.nu` touched the world — read the session-store, read a
   screen, print, read a key — and every other line is pure: `rows.nu`,
   `layout.nu`, `keys.nu`. Three, since the screen read went. `layout render` returns the WHOLE SCREEN as a list of strings and
   never prints (D34, after the bar's `message` and zellij's `commands`), so the
   suite asserts entire frames line for line with no terminal and nothing
   installed. `tests/fake.nu` grew a fake LOCATOR beside its fake display.
   82 assertions, 432/432 overall. It runs IN PLACE (D52) and does not prune (D53).
   **Four bugs the suite could not have found, all found by running it in a
   floating pane and typing at it with `send-keys`:** the default locator table
   never reached `rows build`, because `{}` is not null and `default` does not
   fire on it — so nothing was ever claimed, and the picker showed no places and
   no live previews; `input listen` spells the control modifier
   `keymodifiers(control)`, so ctrl-c typed a `c` instead of leaving; with no
   terminal the loop spun ~37,000 times a second forever, because a caught
   timeout and a caught "there is no terminal" are the same value (it is timed
   now, not trusted); and `dump-screen` without `--session` reads the wrong
   session's pane, because pane ids are per session — an agent living elsewhere
   would have shown a stranger's terminal, silently.
   The filter matches only what the row SHOWS. Folding the agent's message in
   made a two-letter query keep an agent for an invisible reason, at character
   4195 of something it said an hour ago (D57).
   Graphics are deliberately plain — no colour, no glyphs, a `>` for the
   selection. A palette is a separate pass; freezing one now would only mean
   asserting escape codes and revising them later.
   `config.kdl`'s Alt-a is one `nu -n` and nothing else.
7. **Cutover** — ✅ done. **v1 was dismissed early, on purpose** (2026-09-12),
   while this was still incomplete, and DELETED once it was finished. v1's hooks
   are out of `settings.json`, its bar block is out of `sketchybarrc`,
   `CLAUDE.md`'s session-naming rule calls `agent-notify name`, both displays
   are on in `~/.config/agent-notify/config.yaml`, and the prune-daemon is a
   launchd job.

   **Running it for real is what found the remaining defects.** Every one of these
   was invisible to 250+ passing tests, because each needed a real machine, a real
   agent, or a real prune-daemon:

   | found by | defect |
   |---|---|
   | the cutover | a CLI write skipped the dispatch seam, so an agent using the PUBLIC API (P5) never reached a display |
   | the cutover | `push-items` could not know what had VANISHED — an agent that ended left its glyph on its pane forever |
   | a demo pane | `undo-rename-pane` POPS ONE RENAME off a stack; it does not clear our name |
   | a demo pane | "whose event is this" and "whose environment is this" were conflated — identical for a hook, different for a CLI write about another agent |
   | the prune-daemon | a launchd job's PATH is `/usr/bin:/bin`, so `^sketchybar` was silently not found: the prune-daemon pruned correctly and never painted, while dispatch reported "applied" |
   | the prune-daemon | `--force` passed "there was nothing before", so a forced repaint could not release what the prune had just removed |
   | the user | a missing pid was PERMANENT — one failed lookup blinded us to that agent for its whole life |

   **And running it for real is what found the last one**, which nothing above
   could have: `sketchybarrc` still called `"$P/render.sh" scaffold` at every bar
   load — `use ai; ai agent-notify render scaffold`. v1 still parsed and the
   command still existed, so the next reload would have rebuilt its entire item
   pool beside v2's. The bar looked clean only because the cutover had removed
   those items by hand and nothing had reloaded since. This document said
   "nothing invokes it". The bar did.

   Then the deletion, and the promotion (D17). `ai/agent-notify/` is gone, along
   with its five glue scripts in `~/.config/sketchybar/plugins` — so nothing of
   ours lives in anyone else's config directory any more, which was one of the
   things this rewrite was for. `ai` keeps `generate` and `review-loop`; `gg`,
   which imports it, is untouched. The bench lost the two files that measured v1
   exactly as `bench/mod.nu` always said they would, and `floor.nu`'s `use`
   ladder — which used to climb to `use ai`, the whole provider tree a v1 hook
   paid for — now climbs this module's own, so the gap between a leaf and the hot
   cone is measured against the thing §4.4 argued for.

   `agent-notify2` became `agent-notify` in one pass: the directory, every
   reference inside it, the session-store at `~/.local/share/agent-notify/`, and five
   live config files — `settings.json`, `CLAUDE.md`, `sketchybarrc`,
   `config.kdl`, and the launchd plist. The `2` existed so both could be live at
   once; with v1 gone it was only a scar. The bar prefix `an_` stays: it was
   chosen to keep the two apart, and it turns out to be the right name anyway.
   432/432, the session-store intact across the move, both displays painting.

8. **The picker's preview is the message** — ✅ done. The first change made by
   USING the picker rather than by building it, and it reverses D57's first half
   (D58). The preview was `zellij action dump-screen`; it is now the agent's
   stored message, flattened through the same code that fills the bar's drawer.
   **Truer lost to readable.** A dump really is what the agent is DOING, and
   what it looks like is the bottom of a TUI caught mid-redraw — half a spinner,
   a box rule cut off at both edges, an input prompt. The question a picker
   answers is "which of these wants me", and the agent already wrote that answer
   in a sentence. Two smaller things fell out with it: no frame spawns a
   subprocess any more (the heartbeat was doing one every 2 seconds, forever,
   for as long as the picker sat open), and the two codepaths became one — an
   agent with no pane had always fallen back to exactly this.
   **`sketchybar/text.nu` became `core/markdown.nu`.** A flattener with two
   readers is not the bar's, and there was no second answer to have: a message
   is markdown, and neither a SketchyBar label nor a rectangle of terminal
   renders it. Its assertions moved too, into `tests/markdown.nu`. **And what
   stayed behind went where it belonged.** The leftover was one function —
   `quotable`, making text safe to single-quote (D44, D45) — which for a moment
   was a file of its own, which is a smell. Following it found the real fault:
   it was being applied in `render-items`, so the map dispatch diffs held `it’s`
   where the agent had written `it's`, and a row's LABEL was escaped although it
   is argv and never sees a shell. Escaping is what `push-items` does to text on
   the way out, not part of what should be SHOWN. It is now private to
   `items.nu` and called at the single point that writes a quote, `hover-shell`.
   The suite tests the guarantee end to end instead of testing the function: an
   agent's raw text goes in and a command that cannot break out comes back.
   **The locator contract lost a question** (D55): `owns`, `location-label`,
   `go`. A locator now asks only what the multiplexer alone can answer. `screen`
   and its `--session` care are written up in §9b.5, for a `watch` command where
   a whole live terminal would be the point. **And the preview became
   testable**, which it never was: it was the one part of a frame the suite
   could not assert, because asserting it meant running zellij.
   `picker/preview.nu` is pure like everything else in that directory, and
   `picker/mod.nu` is down to three calls that touch the world. 439/439.

> **Reordered after step 1** (was: write API → config → zellij → agent). Two
> reasons. The old step 2 largely landed inside step 1 — `patch`, `changed` and
> validation are done, and what remains of it (write-once policy, `view/`) belongs
> to the steps that actually need it. And the old order built a display before
> anything fed it, so zellij would have been judged against hand-written fixtures.
> The distinction that settles it: **writers need no opt-in, displays do.** An
> agent reporting itself just calls the command; there is nothing to enable. So
> the agent can land before config, and config can wait until a display makes it
> concrete.

---

9. **A session is filed away, not deleted** — ✅ done. The reported symptom was
   that a resumed session came back nameless. The cause was not what §9b.4 said
   it was, and checking took three commands:

   ```
   claude -p …                       → c18dcd01-42cb-405b-bf3a-c128b51ae1a5
   claude -p … --resume c18dcd01…    → c18dcd01-42cb-405b-bf3a-c128b51ae1a5   same
   claude -p … --resume … --fork-session
                                     → 45faab73-2afa-41ef-a888-1bf46d283252   new
   ```

   **A resume reuses the id.** `--fork-session` exists to opt out of it, and
   `SessionStart` even says `source: "resume"`. So the id that would have found
   the name was in the payload all along; what was missing was the thing it
   pointed at, because `SessionEnd` had unlinked it.
   **`name` is the only field a record cannot recompute.** `cwd` and `state` come
   back from the next hook, the pane from `discover-own-location`, the pid from the walk, the
   message from the next `Stop`. A name is authored once — by a human, or by an
   agent following an instruction — and nothing ever says it again. So `drop` was
   the one data-loss event in the system, and it fired on every normal exit.
   The real mistake was one level up: **we modelled a session as a thing that
   exists while it runs.** Claude Code never destroys one; `zellij ls` shows
   exited sessions and `attach` resurrects them; tmux does the same. Every tool
   in the stack says the session is the durable object and *running* is a state
   it is in. We were the only one disagreeing.
   So `SessionEnd` now MOVES the record to `ended/` and a create moves it back
   (D59). The textbook soft delete — a flag on the record, readers filter — was
   measured and rejected: `session-store list` runs on every event and costs 0.4ms at 3
   records, **36.9ms at 600**, so a month of history would have gone straight
   onto every tool call. A second directory the hot path never opens costs
   nothing, and the move is a rename: nothing is read, parsed or rewritten.
   **A restore brings back the SESSION, not the run it was in** — `session-schema
   durable`, which is the core fields and not one namespace. That is the
   session-schema's own line rather than a list of exceptions, and it closes the one way
   this could have done harm: a stale `proc` would let the session-store-garbage-collector prove the
   resumed session dead and file it away again within 30s, and a stale `zellij`
   would rename a pane that had moved on. The defaults still apply on top, so a
   resumed session is idle until you type.
   The session-store-garbage-collector archives too — an agent that was killed is no less resumable than
   one that quit. Reaping is by MTIME and runs ON ARCHIVE, the only moment the
   directory can grow: scanning 600 files costs 2.5ms where parsing them costs
   36.9ms, and the 30s prune-daemon gains no new job. **Seven days** — long enough to
   pick something back up after a weekend, short enough that the directory never
   becomes an archive nobody asked for. `agent-notify session-store list --ended` is the
   way to look.
   **And `agent-notify name` grew `--if-unnamed`**, which is what lets the rule in
   `CLAUDE.md` be one line with no qualification: *run this at every session
   start*. A resumed session already has its name back, so re-deriving one would
   make the stable thing unstable — the flag leaves an existing name alone and
   writes nothing at all. It names only a session that has none: a fresh one, a
   forked one, or one resumed after the keep window. It cannot be a create-only
   `default`, because by the time an agent names itself its record already exists
   — `SessionStart` made it — so a default would never apply and a fresh session
   would never get named.
   452/452. The hot path is untouched — `ended/` is not in any read it makes.
   **Also measured, and deliberately not acted on:** SQLite. `nu` has good
   builtin support, and it beat the JSON session-store on every axis — 0.12ms to write
   against 0.46ms, 0.12ms to read the live set against 0.41ms at three records
   and 36.9ms at six hundred, and eight concurrent writers doing 320 updates with
   zero failures, which is the contention D8 was locked against. Not taken here:
   the record is an open session-schema (D11c) so it would live in a JSON column, `cat
   sessions/<id>.json` stops being how the session-store is inspected (P5 leans on that),
   and the cold cost inside a real hook was never measured. Reopening D8 deserves
   its own step, not a decision made on the way past.

---

## 9b. Deferred — what is not built, and what each one waits on

Every step in §9 is done. These are not unfinished steps; they are work set
aside on purpose, each for a reason that has not changed. Written down because
the alternative is rediscovering them — and because the first and the third are
blocked on a DECISION rather than on effort, which is a different kind of
waiting and needs saying out loud. §9b.5 is the odd one: the code for it was
written, integration-registry, lived with and deleted, and what is deferred is
the SHAPE it should have come in. The fourth is not work at all: it is a
behaviour that looks like a bug and is not, recorded so it does not get filed as
one.

### 9b.1 A click on a bar row should jump

**What it is.** v1 did this and this does not: clicking an agent in a drawer
takes you to its pane. It is the only thing v1 did that is still missing.

**Almost all of it exists.** The rows are already items
(`an_<state>.row.<i>`), the jump is already a command, and D44 already settled
how a bar item answers without spawning anything of ours: bake the answer in at
PAINT TIME, as a shell command line, because the paint already knows which agent
is in which row. So the click script is one generated line per row with the
agent's id in it — no lookup, no nushell, no second process. v1 proved the
mechanism with `jump.sh`; what it did not have was D44.

**What blocks it is the RAISE, and only the raise.** A bar click arrives from a
desktop, not from a terminal, so before focusing a pane you have to bring the
terminal's WINDOW to the front — and that is a window manager's job. The picker
never needed this, which is exactly why the picker integration-registry first:
it runs inside the terminal, where the window is already in front.

D50 says this module names no window manager and assumes no operating system.
v1 broke both — it called aerospace, fell back to `open -a Ghostty`, and read
the attached session out of the WINDOW TITLE. So the click waits for an answer
that keeps D50 true. Three shapes, none chosen:

| | |
|---|---|
| a setting | `sketchybar.commands.raise: [<program>, <args>…]` — user-supplied argv, run before the jump. Names no program, assumes no OS, and is empty by default. Sketched during step 6, not built |
| nothing | focus the pane and let the user bring the window up themselves. The jump is still correct; it just is not complete |
| the terminal's own | many terminals can raise themselves from a CLI or a URL scheme. Correct per terminal, which makes it the same problem one level down |

The first is the only one that has survived a reading so far, and the user has
deferred the question twice. It should be taken on its own, not folded into
another step.

### 9b.2 A palette for the picker — DONE (step 10, D62 and D64)

**What is done.** The PREVIEW is painted, and only its two kinds: a heading in
`yellow_bold` and a code block in `blue`, which on this machine's Rosé Pine are
rose and iris — the same two meanings the drawer paints, said in each display's
own vocabulary. `INK` in `layout.nu` is the whole of it, and a kind that is not
in that map is not painted at all.

**All three constraints below held**, and the way they held is the part worth
copying. Colour goes on LAST, after `clean` and `clip`: the strip stays a
defence against an escape in an agent's own text, the clip still measures what a
reader sees, and the suite's whole-frame assertions stay escape-free because the
kind they use (`text`) is not in the map. One assertion pins the ordering
directly — a painted row, clipped to a narrow pane, is still the right width
after `ansi strip`.

**And then the rest of it (D64).** The list, the rules and the footer. A state
wears the colour it wears on the bar and in the pane titles — foam turning, gold
talking to you, love stuck — the selection is rose, a location is dim, and a key on
the footer is iris because a key is a thing you invoke. The mechanism is what
made it small: a line is built as `{c, t}` PIECES and inked last, so the same
eight lines lay out a row, a bar and a preview line.

**Two things it had to decide, and one it had to not break.**

- **ANSI names, or hex?** The old picker used ANSI NAMES on purpose: the bar
  sits on a desktop and picks its own colours, but a terminal has a theme and
  the display inside it should obey. That reasoning survives even though the
  code that held it does not.
- **Where does it come from?** Not the config file. The picker reads no settings
  and that is a constraint, not an omission (D48, D54) — so the palette is a
  constant in `layout.nu` or it is nothing.
- **THE SUITE ASSERTS WHOLE FRAMES, line for line** (D34). Colour introduced
  naively turns every one of those assertions into an escape-code diff, which is
  how a readable suite becomes an unreadable one. The precedent is the old
  `tests/browse.nu`, which stripped colour before comparing — `$s | ansi strip`
  — on the grounds that colours are real but are the one thing a test should not
  freeze, since they follow the terminal's theme. That is three lines and it
  keeps §9b.2 from costing the thing that made the picker testable.

### 9b.3 D16 — where the bench harness lives

Still genuinely open, and the only OPEN row left. ~350 lines under `bench/`, not
part of the module — nothing in `mod.nu` imports it, so `use agent-notify` never
parses a byte. §8 promises every step re-measures, which is why it is in the
repo rather than in a scratch directory. The question is only whether that is
where it stays now that the steps are done.

### 9b.5 A `watch` command — the live pane, where it belongs

**What it is.** `agent-notify watch <who>`: one agent's real terminal, followed
in place, without taking your pane to it. The code existed and worked —
`integrations/zellij/locate.nu`'s `screen`, deleted in step 8 with the preview
that used it (D58).

**Why it was left.** Not for want of a mechanism. A live screen wants a WHOLE
terminal, a refresh faster than 2 seconds, and no chrome competing with the
agent's own TUI. The picker gave it eight lines beside a list and a footer,
which is where it looked worst; a command of its own is where it would look
right. Nothing about the picker is in the way, and nothing has to change there.

**What is already known, so it is not re-probed.** `zellij action dump-screen
--pane-id terminal_N` reads any pane in ~12ms. `--session` IS NOT OPTIONAL —
pane ids are per session, so without it you read whichever session the process
is attached to and silently show a stranger's terminal (§11). A dump races the
redraw. And `browse` runs in place (D52), so a watcher must notice when the pane
it is asked to show is its OWN — the deleted code did.

### 9b.4 ~~Known and accepted: a resumed session starts nameless~~ — FIXED in step 9

**Wrong, and fixed** (2026-09-13). This said a resumed session gets a NEW id
from Claude Code and that carrying a name across would need a heuristic. Both
halves were false, and neither had been checked: `--resume` hands back the SAME
id (`--fork-session` exists precisely to opt out of it), so the id that would
find the name is in the payload — we had simply deleted what it pointed at. See
step 9.

---

## 10. Nushell notes (hard-won)

Things that cost time once and should not cost it twice. All verified on
0.115.1.

**A def named after a builtin shadows that builtin for every module the file
imports** — whatever the order of the `use` statements, and the error displays
somewhere else entirely. `core/session-store.nu` defining `export def get` made
`core/session-schema.nu` fail to parse on `get -o $f` with "the `get` command
doesn't have flag `-o`", a file that never mentions `get` as a name. Worse, a
*bare* `get $x` in that position would not error at all — it would silently call
ours.

| | |
|---|---|
| `export def get` (before or after `use`) | poisons imported modules |
| `export def read` | fine |
| `export def "session-store get"` | **fine** — multi-word subcommands are exempt |

So: library functions avoid builtin names (`read`/`remove`, not `get`/`drop`),
and the command set uses multi-word names, which is what we wanted it to read
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

**Records compare structurally and order-insensitively** (`{a:1,b:2} ==
{b:2,a:1}` is true, nested too), which is what lets `changed` be a plain `!=`
rather than a canonicalising walk.

**Running a file as a script with `main` + arguments costs ~7.5ms more than the
same file imported as a module**, because nu evaluates twice — a synthetic
command line on top of the file itself (`eval_source <commandline>` nested
inside `evaluate_file`, visible under `--log-level perf`). A script with only
top-level code does not pay it. Measured on the real entry: 29.3ms as a script
against 20.4ms via `-c 'use <abs path>; hook <Event>'`, which is why the hook
command line is spelled the second way.

> That rule bit three times in one afternoon while writing the agents: `def
> ignore` (shadowing the builtin the next line pipes to), `export def all` in the
> test runner, and `export def get` in step 1. It is the sharpest edge in the
> language as far as this module is concerned. A related one: **a module cannot
> export a command with its own name** — `agents.nu` must export `main`, not
> `agents`.

**Reading stdin blocks until the writer closes it.** `open --raw /dev/stdin` in
an entry point run by hand hangs with no clue why; `is-terminal --stdin` guards
it.

**A module reached by two import paths is PARSED TWICE.** There is no cache
across `use` paths, and the cost is worse than additive. Measured:
`session-store.nu` alone +1.32ms, `zellij.nu` (which imports it) alone +2.25ms,
both together
+4.51ms where a re-parse alone predicts +3.57ms. Keep the import cone a tree:
the fix was to stop a display importing the session-store at all, which took the
whole dispatch cone from +5.28ms to +3.87ms per event.

**Private Use Area glyphs do not survive ordinary tooling.** Nerd Font icons
written as literal characters arrived in the file as empty strings — silently,
with no error anywhere. Write them as `"\u{f021}"`. The tests caught it only
because they asserted a title's exact contents.

**A LAUNCHD JOB'S PATH IS SMALLER THAN A HOOK'S**, which is smaller than your
shell's: the prune-daemon runs with `/usr/bin:/bin` and nothing else, so
`^sketchybar` and `^zellij` silently did nothing there — the prune-daemon pruned
correctly and never painted, while dispatch reported "applied". Every external
program a display calls is now resolved to an ABSOLUTE path in `settings`, where
a missing one is a loud error instead of a display that paints nothing. The same
rule already applied to `nu` itself in the help-setup blocks; it applies to
everything.

**`job spawn` runs a thread INSIDE the process.** It dies when that process
exits, and so does any external command it started — both verified. Nothing a
hook spawns can outlive the hook, so nothing spawned can look again later.

**The builtin-shadowing rule bit a FOURTH time**, and this one was the most
remote: `tests/mod.nu` exported `def all`, which silently broke `| all { … }`
inside `tests/prune-daemon.nu` — a file that never mentions the name and was
written weeks later. The runner is `export def main` now, so it is spelled
`tests` and can poison nothing. When a library command wants a builtin's name,
the answer is always the same: pick another name, or make it multi-word.

**Some names are PARSER KEYWORDS and cannot be commands at all** — `run` among
them. A louder failure than builtin shadowing (it names the rule and refuses to
parse) but the same lesson: check the name before building on it. `dispatch
project`, not `dispatch run`.

**A def annotated `-> nothing` cannot END in `error make`**, because `error` is
not `nothing`. Drop the return type on commands whose job is to fail.

**A comment may not sit between an `@attribute` and its `def`.** "Attributes
must be followed by a definition" — put the prose above the attributes.

**An operator cannot start a continuation line, and a boolean expression does
not continue across lines at all.** A leading `and` is read as a command
(`Command 'and' not found`); moving it to the end of the previous line gives
"incomplete math expression" instead. Bind the halves with `let` and compare
them on one line.

**A flag cannot start a continuation line.** `summarise (…)\n  --title "x"` is a
parse error; bind the argument to a `let` and keep the call on one line.

**`ls` on a glob that matches nothing is an ERROR**, not an empty list — and a
directory that outlives its contents is the ordinary case for a session-store
whose last agent has just ended. `try { ls … } catch { [] }`, or the first empty
session-store takes every display down with it.

**`reject` errors on a missing column**; `reject --optional` does not.

**Intermediate pipelines print nothing under `nu -c`** — only the final one — so
anything a script means to show needs an explicit `print`.

**An error raised INSIDE a `catch` block escapes that `try`** — and nushell then
reports the ORIGINAL error, at the ORIGINAL span. So it looks exactly like a
`try` that does not catch, and you will go looking in the wrong place. Found by
writing `catch {|e| {msg: $e.msg, json: ($e | to json)} }`: **`to json` throws
on a caught error record**, the catch died, and the report pointed at the `input
listen` two lines above. `$e.msg` is safe; nothing else in a catch should be
able to fail.

**`input listen --timeout` THROWS on expiry** rather than returning null, so a
heartbeat is a caught error. And the catch must be able to tell that expiry from
"there is no terminal", which arrives the same way: with stdin closed the loop
turns over **~37,000 times a second, forever**. Time it rather than matching the
message — a listen that failed in far less than the timeout was not a timeout,
and the wording belongs to nushell.

**`input listen` spells a held modifier `keymodifiers(control)`**, not `control`
— a Debug format leaking into the record. `"control" in $ev.modifiers` is false
for every control key there is, so ctrl-u types a `u` and ctrl-c types a `c`
instead of leaving. Match on CONTAINS so both spellings work. The suite could
not catch this: it builds its own events, spelled the way the docs say.

**`term size` answers 80×24 when there is no terminal** rather than failing, so
it cannot be used to find out whether there is one.

**An explicit `{}` is not null, so `default` does not fire on it.** "Use the
integration-registry table" and "use an empty table" must not be spelled the
same way — they were, and the picker silently claimed nothing, previewed nothing
and showed no places until it was run. Relatedly: a LITERAL `null` cannot be
passed to a typed optional parameter (parse error), but a VARIABLE holding null
can, and `default` then works — which is how an optional is threaded through a
caller.

**`str downcase` is deprecated** (0.114) in favour of `str lowercase`.

**Arithmetic does not continue across lines either**, with the operator at
either end — the same rule as booleans. `+ (…)` on its own line is read as a
fresh pipeline and fails with "Command `+` not found".

---

## 11. Platform notes (hard-won)

Not nushell — the programs underneath. Same rule as §10: cost time once, not
twice.

**zellij**

- `undo-rename-pane` / `undo-rename-tab` **pop one rename off a stack**. They do
  not clear our name. After a session's worth of state changes, an undo leaves
  the second-to-last agent title sitting there. Write the name you want instead;
  blank-means-undo is right only for a pane that never had one.
- **There is no tab environment variable.** `ZELLIJ`, `ZELLIJ_PANE_ID` and
  `ZELLIJ_SESSION_NAME`, and nothing else — so learning which tab a pane is in
  costs a `list-panes`.
- `action list-panes -t -j` is the one call worth making: a flat list of panes
  with `id`, `title`, `tab_id`, `tab_name`, `tab_position`, `pane_command`,
  `pane_cwd`, `is_plugin`, `exited`. It answers pane→tab, tab names and liveness
  at once.
- **`tab_id` is not `tab_position`.** `rename-tab --tab-id` wants the id; ids
  are not renumbered when tabs move, and `query-tab-names` returns names in
  POSITION order with no ids, so it cannot be used for renaming.
- **`action dump-screen --pane-id` reads ANY pane's live screen** for **12ms**.
  `--full` for scrollback, `--ansi` to keep styling, `--path` to a file. It was
  the picker's preview until step 8 (D58) and nothing calls it today; the note
  stays because §9b.5 wants it back, in a command where a whole terminal is the
  point.
- **PANE IDS ARE PER SESSION, so `--session` is not optional.** Probed with two
  sessions, both holding a pane 0 and different contents: `action dump-screen
  --pane-id terminal_0` with no `--session` reads whichever session the process
  is attached to. An agent living anywhere else would show A STRANGER'S
  TERMINAL, silently, with no error — the same failure class that got the
  screen-scraping picker rejected. `jump` always passed `--session`; so must
  anything else.
- `action send-keys --pane-id <id> "Down" "Ctrl u"` drives any pane's keyboard
  **without focusing it**, and `action close-pane --pane-id` closes any pane,
  not only the focused one. With `dump-screen`, that is the whole technique for
  testing an interactive program: `zellij run --floating … -- nu -n probe.nu`,
  screenshot it, type at it.
- **A dump races the redraw.** `send-keys` then `dump-screen` in the same breath
  shows the frame BEFORE the key. Dump twice; several "it did not work" findings
  were this.
- `--session <name>` on every action makes it work from anywhere, including a
  process with no ambient `$ZELLIJ`.
- **It exits 0 whether or not the action worked.** The reason arrives on STDERR:
  `Pane with id Terminal(99999) not found`, `Session 'x' not found`. The exit
  code is worthless; stderr is the whole answer — the same shape as macOS `ps`
  below.
- …and stderr is not only for failures. `Pane Terminal(3) is already focused` is
  a jump that SUCCEEDED. So the benign messages have to be named and everything
  else raised; the other way round makes a real failure silent.
- **`switch-session` CREATES a session it cannot find**, so a stale name does
  not fail — it spawns an empty session and takes you there. Check
  `list-sessions --short --no-formatting` before switching. (`--short` prints
  one bare name per line, which is the only parseable form.)
- A pane is `terminal_7` to `switch-session --pane-id` and either `terminal_7`
  or `7` to `focus-pane-id`. The session-store holds the short form.
- `zellij action list-clients` shows which clients are attached and which pane
  each one has focused — the only way to tell whether a session is being LOOKED
  at, as opposed to merely running. `ps` cannot: a client's argv still says
  `zellij attach <original>` after it has switched sessions.
- `delete-session <name> --force` removes a running session; without `--force`
  it refuses and says so.

**Claude Code**

- **IT WRITES ITS OWN TERMINAL TITLE, AND THAT TITLE WINS.** zellij lets a
  terminal-emitted OSC title overwrite a name set by `action rename-pane`, and
  Claude Code repaints its own ("◐ <session summary>") right after every hook —
  so a pane rename lands and is clobbered a moment later. v1 found this the hard
  way; **v2 depends on the fix and never mentions it**, which is why it is here:
  `"env": {"CLAUDE_CODE_DISABLE_TERMINAL_TITLE": "1"}` in
  `~/.claude/settings.json`. Remove it and every pane title in this module
  silently stops working, with nothing in any log. It takes effect for NEW
  sessions only. Diagnosis: `zellij --session S action list-panes -t -j` and
  look at `title` — a Claude spinner glyph there means the OSC won.
- **`--resume` REUSES THE SESSION ID.** `--fork-session` exists to opt out and
  mint a new one. `SessionStart` also carries `source`: `startup`, `resume`,
  `clear`, `compact`. Probed with `claude -p … --output-format json`, which
  prints the id it used — the cheapest way to keep-in-view any question of this
  shape.
- **`--settings <file>` REPLACES the user's settings rather than merging**,
  which makes it the safe way to probe hook payloads: point a throwaway
  `SessionStart` hook at `cat >> somewhere` and the real hooks never fire.
- **Hooks are loaded at session start**, so a `settings.json` edit reaches only
  sessions started after it. Half a fleet on the old help-setup is the normal
  state of things for an hour after any change.
- **A subagent's tool calls carry the PARENT's session id**, so they fold into
  the parent's record for free — and `SubagentStop` must be ignored, or the
  parent reads as finished while it is still working.

**SketchyBar**

- A message costs what a process costs and almost nothing per property: `--set`
  with one property 6.59ms, with ten 6.54ms. **Batch everything into one call.**
- `--add` + `--remove` of a single item is 17.51ms, ~3× a whole repaint. Create
  the item pool ONCE and never touch it again — v1 learned this by pinning the
  daemon near 40% CPU.
- `--query <item>` returns JSON with `script`, `click_script` and `update_freq`
  under `scripting`, not at the top level.
- **An item's `script` is run by a SHELL**, so it can be a whole command line
  rather than a path to one. That is what lets a hover answer without starting a
  second interpreter (D44).
- Inside single quotes a script's `$HOME`, backticks and `--flags` are all
  literal — probed, not assumed. Only `'` can break out (D45).
- **A `script` also runs on a forced `--update`**, which the bar sends at load,
  with `SENDER=forced`. Every script needs a `[ "$SENDER" = … ] || exit 0` guard
  or the bar opens things nobody hovered.
- `mouse.exited.global` IS delivered to a `drawing=off` item, so a behaviour
  that never changes can live on an invisible item of its own instead of being
  rewritten onto a visible one by every paint.
- `--add` of an item that already exists is a no-op, but `--remove /regex/` is
  the only way to shrink a pool; the regex needs the literal dot (`/an_x\..*/`)
  to spare the parent item.
- A popup is `popup.<parent>` as a position, and `popup.align=left` opens it
  rightward — `align=right` runs it off the screen edge.
- 74 items with subscriptions and full styling cost **117ms in one `--add`
  message**, and a 70-property `--set` costs 18.6ms. Creating the pool once and
  setting into it forever is worth roughly an order of magnitude.

**launchd**

- `StartInterval` needs no daemon of ours: no daemon, no lock file, no pid to
  supervise, and it survives logout and reboot.
- **A job's PATH is `/usr/bin:/bin`.** Every program a job calls needs an
  absolute path — this silently broke the prune-daemon's repaint while its prune
  worked fine.
- `bootstrap gui/$UID <plist>` to load, `bootout gui/$UID/<label>` to unload;
  bootout first when reinstalling, and ignore its failure when nothing is
  loaded.
- `launchctl list | grep <label>` gives pid and last exit status — the only
  cheap way to notice a tick that fails every 30 seconds. Set
  `StandardErrorPath`.

**systemd** — written from the documentation, NOT yet watched on real hardware.
Everything below is asserted against the generated file text; the lines marked
UNVERIFIED are the ones a Linux box has to settle.

- **`AccuracySec=` defaults to ONE MINUTE, and that default is a silent lie for
  any sub-minute timer.** systemd.timer(5): the unit elapses within a window
  from the scheduled time to `AccuracySec` later, and inside that window "the
  expiry time will be placed at a host-specific, randomized, but **stable**
  position that is **synchronized between all local timer units**". Stable and
  synchronized, not jitter — every timer on the machine lands on one shared
  grid. Follow a 30s timer through a 60s grid: fire at T, next elapse T+30,
  window [T+30, T+90], which contains exactly one grid point. Steady state: a
  30-second timer that fires every 60 seconds, forever. Pin it (D68).
- It is a **per-unit** setting in `[Timer]`. The global one is a different name
  in a different file — `DefaultTimerAccuracySec=` in `systemd/user.conf` — and
  the per-unit value overrides it, so there is never a reason to touch it.
- **`%` is a specifier in every value**, expanded before quoting is even
  considered. A literal one must be doubled. A `%` in a home directory would
  otherwise silently become something else.
- **`ExecStart` is a command line and `StandardError=append:` is not.** The
  first is split on whitespace with C-style escapes inside quotes, so every
  argument is quoted; the second takes a path, and quoting it would put the
  quotes IN the filename.
- Two files, linked by name: a `Type=oneshot` `.service` and a `.timer`.
  `[Install] WantedBy=timers.target` is what makes `enable` possible.
- `daemon-reload` BEFORE `enable --now`, or a re-install silently runs the file
  systemd read last time — the old interval, with no complaint.
- `disable --now` before deleting the files: `enable` leaves a symlink outside
  our two paths, and that is the one thing deleting them would strand.
- `systemctl --user show <unit> -p A -p B` prints `KEY=VALUE` lines and **exits
  0 for a unit that was never installed**, values just empty — so `installed` is
  the file on disk, never systemd's opinion. `ExecMainStatus` on the SERVICE is
  the last tick's exit code; the timer only reports on itself.
- **The binary existing is not the question.** WSL1 and many containers ship
  `systemctl` with no user manager behind it, so the probe is `systemctl --user
  list-units` exiting 0 — the call that needs the same user bus everything else
  here needs.
- UNVERIFIED: what happens after the machine sleeps through several intervals.
  launchd fires once on wake. `Persistent=` does not help either way — it
  applies to `OnCalendar=`, not to monotonic timers.
- UNVERIFIED: `OnActiveSec=1s` as the `RunAtLoad` equivalent, and whether
  `StandardError=append:` on a `oneshot` behaves as expected across the systemd
  versions in the wild (it needs ≥ 240).

**macOS `ps`**

- `ps -o ppid=,lstart=,comm= -p <pid>` is one line: ppid, then `lstart` as FIVE
  whitespace-separated tokens, then the command.
- `ps -o pid= -p a,b,c` returns only the pids that are alive and exits 1 when
  none are — but it also exits 1, **with something on stderr**, when a pid is
  out of range. Stderr is what tells "none alive" from "the question was wrong".
- A pid alone does not identify a session: pids are recycled. Store the start
  time with it.
