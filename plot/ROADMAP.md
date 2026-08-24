# `plot` 2.0 — meta-plan

## Where we are

**Ground truth verified 2026-08-23:**

| thing | state |
|---|---|
| zellij | **0.45.0 from brew** — KGP is in a tagged release, no dev build needed |
| terminal | Ghostty (native KGP) |
| `chafa` | 1.18.2 |
| `vl-convert` | 1.9.0 |
| `plot` on `main` | 6 files, ~900 lines: spec builders → `vl-convert` → file → `start` |
| `feat/plot-perspective-workbench` | **stale, to be deleted** (Docker + Perspective.js experiment) |
| prior "P1/P2 done" notes | **fiction** — no inline-render or stash code exists in this repo |

So: clean slate, and the one hard external blocker (KGP in a released zellij) is gone.

## Where we're going

Two horizons, one architecture.

**Horizon 1 — the shell as a notebook.** Data manipulation and plots interleaved
in one nushell pane, plots rendered inline. Shell-native, not notebook-file-native:
no `.ipynb`, no cell server, no kernel. Your scrollback *is* the notebook.

**Horizon 2 — the shell as Grafana.** Three cooperating panes:

```
┌──────────────────────┬──────────────────────────────┐
│ scratch              │  display                     │
│ nushell REPL:        │  ┌────────────┬────────────┐ │
│ scrape, wrangle,     │  │  panel A   │  panel B   │ │
│ publish datasets     │  ├────────────┴────────────┤ │
├──────────────────────┤  │  panel C                │ │
│ query                │  └─────────────────────────┘ │
│ define panels        │                              │
└──────────────────────┴──────────────────────────────┘
```

## The architectural spine

Everything below hangs off one idea: **four planes, cleanly separated.**

| plane | owns | lives in |
|---|---|---|
| **data** | named datasets, session-scoped | on disk, written by scratch |
| **definition** | panels = query + chart spec + slot | on disk, edited by query pane |
| **render** | (data + spec) → pixels in a pane | the render kernel |
| **control** | *when* to re-render, and where | the rig |

Horizon 1 needs only **data + render**. Horizon 2 adds **definition + control**.
That's why one plan reaches both: Horizon 2 is Horizon 1 plus two planes, not a
rewrite.

Cross-pane communication is the crux. Separate panes are separate nushell
processes with no shared memory, so the data plane is the IPC. Choosing its
format and its change-notification mechanism is the single highest-leverage
decision in this plan — hence Phase 1.

---

## Status

| phase | state |
|---|---|
| **0 — Ground truth** | ✅ done — see `.notes/phase0-findings.md` |
| **1 — Architecture** | ✅ agreed — see `ARCHITECTURE.md` (D1–D5 settled, D6 open) |
| **2 — Kernel** | ✅ done — `render/` + `lib/state.nu`, 70 tests green |
| **3 — Horizon 1** | ✅ **usable now** — inline by default; 3.3 discussion still open |
| **4 — Panels** | not started |
| **5 — The rig** | not started |

**Horizon 1 is reached**: charts draw inline in the terminal with no flag,
`--out` writes a file without opening it, `--spec` returns the Vega-Lite spec.

Shape of the rewrite (vs the pre-rewrite commit `ca4629d`):

|  | before | after |
|---|---|---|
| module | 917 lines, 6 files | 1245 lines, 23 files |
| largest file | **558** (`mod.nu`) | **148** (`render/vega.nu`) |
| tests | none | 665 lines, 70 tests |

It grew because it gained things it did not have: the whole terminal render
layer, session state, and three times the completers. What shrank is the part
that mattered — no file is now big enough to hide a bug in.

Reuse: `line`, `scatter`, `bar`, `step` and `impulses` share one 54-line body
(`charts/common/draw.nu`); each command supplies only its mark. Of what is left
in a chart file, most is the flag signature — **nushell cannot compose command
signatures**, so those ~20 lines per command are irreducible. Their executable
bodies are 3–8 lines.

**Next**: the 3.3 discussion — what "more shell-like than Jupyter" should
concretely mean — before Phase 4 introduces panels.

## Phase 0 — Ground truth *(exploration, me, solo)*

I cannot design the render plane until I know what the terminal will tolerate.
Every question below has bitten inline-image tooling before.

**0.1 — KGP capability probe.** A scratch harness, not module code. Answers:
- raw APC escapes vs `chafa --format kitty` — which is more controllable?
- do images survive **pane resize**? scrollback? pane focus change?
- image **ids and deletion** — can I replace panel A's image in place, or does
  every redraw append?
- multiple simultaneous images in one pane
- what happens on `clear`, and in alternate-screen apps
- exact **sizing**: cells → pixels, and who does the scaling (us, chafa, or the
  terminal)

**0.2 — Latency budget.** Time `vl-convert` end-to-end at realistic data sizes
(1k / 50k / 500k rows). This decides whether the reactive model in Phase 1 can be
"re-render on change" or must be "re-render on demand". If a chart costs 2s, the
whole UX changes.

**0.3 — zellij control surface.** What 0.45 gives us for the control plane:
`zellij pipe`, `zellij action`, KDL layouts, whether a pane can be told to re-run
something, pane naming/addressing from inside a pane.

**Deliverable:** a findings note + a minimal working image-in-pane primitive.

**Gate G0 — I report, we decide.** If KGP has a nasty limitation (e.g. images
don't survive resize), the display-panel design changes shape and we adapt Phase 1
before writing any real code.

---

## Phase 1 — Architecture agreement *(discussion, you and me)*

I write a proposal, you push back, we converge. Open questions listed in
"Questions for you" below. The five decisions:

1. **Chart backend** — keep Vega-Lite/`vl-convert`, or change?
2. **Data plane** — format, location, lifecycle, size ceiling
3. **Panel/query model** — what a panel *is*, and how you define one
4. **Reactivity** — manual / on-change / timer, and who watches
5. **Layout ownership** — zellij KDL layout vs a single-pane TUI we draw ourselves

**Deliverable:** `ARCHITECTURE.md` in this repo — the contract for Phases 2–5.

**Gate G1 — you sign off.** No implementation before this.

---

## Phase 2 — The kernel *(implementation)*

Small, boring, tested. Both horizons stand on this, so it gets built once and
properly. Per the modularization preference: nested submodules, small files.

```
plot/
  render/    image → pane: sizing, placement, ids, replace, clear
  store/     named datasets: put / get / list / drop, session-keyed
```

No charting yet. The point is that `render` doesn't know what a chart is and
`store` doesn't know what a plot is.

**Deliverable:** kernel + a `nutest` suite. This is where testing discipline
starts, since `main` currently has none.

---

## Phase 3 — Horizon 1: the notebook shell *(implementation + one discussion)*

3.1 Rebuild the chart layer (`plot line|scatter|bar|…`) on top of the kernel,
    inline-by-default, file output only when asked.
3.2 Port the Rosé Pine theming and completions from the current `main`.
3.3 **Discussion checkpoint:** what does "more shell-like than Jupyter" mean to
    you *concretely*? Re-runnable cells? A history of (code → plot) pairs? Or is
    inline rendering plus dataset publishing already the whole of it? I have a
    guess but I'd rather ask than build the wrong thing.

**Milestone: Horizon 1 usable daily.** Everything after this is additive — a good
place to stop, live with it, and let real use inform Horizon 2.

---

## Phase 4 — Panels and queries *(implementation)*

Introduces the **definition plane**.

- panel registry: add / edit / remove / list
- a panel binds a **query** (nushell source over the data plane) to a **spec**
- dependency tracking: which panels read which datasets — the prerequisite for
  any reactivity beyond "redraw everything"

Still single-pane at this stage: you can define and render panels without the rig.
That keeps Phase 4 testable on its own.

---

## Phase 5 — The rig *(implementation)*

Introduces the **control plane** — the actual Grafana feel.

- a zellij KDL layout wiring scratch + query + display
- `plot rig up` / `down` / `status`
- the display pane's render loop and slot geometry
- change propagation, using whichever mechanism Phase 0.3 and Phase 1 chose

**Milestone: Horizon 2 reached.**

---

## Phase 6 — Hardening

Error surfaces, docs/README, completions, test coverage, and a pass to delete
whatever turned out to be scaffolding.

---

## How we work through this

- **Exploration steps** I do alone and report back with findings, not conclusions.
- **Discussion steps** are real gates — I won't code past one.
- **Implementation steps** I narrate as I go: what I'm building, why that way, and
  what I'm deliberately leaving out.
- Anywhere I hit a fork mid-implementation that Phase 1 didn't settle, I stop and
  ask rather than picking silently.

## Housekeeping

- delete `feat/plot-perspective-workbench`
- branch off `main` before Phase 2 — nothing lands on `main` unreviewed
- the `~/.config/nushell/scripts/plot` symlink already points here, so edits are live
