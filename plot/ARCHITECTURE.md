# `plot` 2.0 — architecture

Phase 1 deliverable. This is the contract for Phases 2–5. Informed by the
Phase 0 probes (`.notes/phase0-findings.md`), not by assumption.

## Principles

1. **One render path.** Probe Q5/Q6 showed KGP images are *cell-anchored*: they
   resize with the pane and scroll with the text. So "plot in scrollback"
   (notebook) and "plot pinned in a panel" (dashboard) are the same operation
   with a different cursor origin. We do not build two renderers.
2. **Spec builders never render.** `plot line` returns a Vega-Lite spec record.
   Rendering is a separate, explicit step. This is what makes one render path
   serve both horizons, and makes caching possible at all.
3. **The data plane is the IPC.** Panes are separate nu processes with no shared
   memory. Datasets on disk are how they talk. No daemon.
4. **Small files, nested submodules.** Per standing preference.

## The four planes

### 1. Data plane — named datasets

```
${PLOT_STATE:-~/.local/state/plot}/<session>/data/<name>.nuon
                                             /<name>.meta.nuon
```

`<session>` = `$env.ZELLIJ_SESSION_NAME`, falling back to `$env.PLOT_SESSION`,
then `default`. Keying by zellij session means sibling panes in one session
share datasets automatically, and two sessions don't collide.

- format: **nuon** now. The store API takes/returns nu values and never leaks the
  format, so parquet can slot in later for big frames without touching callers.
- sidecar meta: row count, columns, written-at, content hash. The hash is what
  lets the control plane skip work.
- API: `plot data put|get|list|rm`

### 2. Render plane — image into cells

The best-understood plane, because Phase 0 measured it.

- `caps.nu` — query cell pixel size (`ESC[16t`), cache per process.
  **Never use `ESC[14t`** for pane geometry: it reports the outer Ghostty
  window, not the pane (see findings).
- `geom.nu` — pane cells x cell px => image pixel box.
- `kgp.nu` — chunked base64 transmit, image ids, delete, cursor save/restore.
- `cache.nu` — `hash(spec) -> png`. vl-convert is 370–630ms and dominates
  everything; it is the only thing worth caching.

Two modes, one code path:

| mode | origin | id | used by |
|---|---|---|---|
| **flow** | current cursor | fresh | notebook (Horizon 1) |
| **slot** | explicit `row,col` | stable per panel | dashboard (Horizon 2) |

Slot refresh sequence, forced by probe Q2 (id reuse redraws **at the cursor**,
not in place):

```
save cursor -> move to slot origin -> delete old id -> transmit new -> restore cursor
```

### 3. Definition plane — panels

A dashboard is a **nushell file you edit in your own editor**:

```
${PLOT_STATE}/<session>/dashboard.nu
```

It's `.nu` and not a config format because the queries *are* nushell code —
so you get highlighting, LSP, and `use` for free, and it's git-trackable.

```nushell
export def panels []: nothing -> list {
  [
    {
      name:  "cpu"
      slot:  {row: 0, col: 0, w: 1, h: 1}
      query: {|| plot data get metrics | where host == "web1" }
      chart: {|d| $d | plot line --x ts --y cpu --title "CPU" }
    }
  ]
}
```

`chart` returns a spec (principle 2), so the same closure works for a panel, for
a one-off inline render, or for a PNG on disk.

### 4. Control plane — when and where to redraw

**Decided: one zellij pane per panel, arranged by a KDL layout.**

zellij owns geometry, borders, titles and resize; we own only "draw my chart in
my pane". Each panel pane redraws itself at its own origin, so the grid maths and
the atomic-redraw problem both disappear, and you can rearrange or resize panels
with the zellij keys you already use.

**Decided: refresh is manual.** No watcher, no polling, no automatic
re-render on data change. A panel redraws when told to.

That leaves one open mechanism question for Phase 5 (**D6**): how a refresh
request reaches N panel panes. Candidates, cheapest first:

- `plot rig refresh` uses `zellij action write-chars` to type the render command
  into each panel pane (crude, zero infrastructure)
- each panel pane runs `plot panel serve <name>`, blocking on a per-session
  signal file that `plot rig refresh` touches (clean, still manual-triggered)

`zellij action` is the pane-control path; `zellij pipe` is plugin-only.
Pane ids come back from `zellij action new-pane` on stdout, so panes are
addressable once created.

## Module layout

```
plot/
  mod.nu
  kernel/
    render/  caps.nu  geom.nu  kgp.nu  cache.nu  mod.nu
    store/   paths.nu  put.nu  get.nu  meta.nu  mod.nu
  chart/     line.nu  bar.nu  scatter.nu  histogram.nu  step.nu  impulses.nu
             spec.nu  appearance.nu  theme.nu  colors.nu  mod.nu
  panel/     registry.nu  slot.nu  render.nu  mod.nu
  rig/       layout.nu  panes.nu  refresh.nu  mod.nu
  layouts/   dashboard.kdl
```

`kernel/` knows nothing about charts. `chart/` knows nothing about panels.

## Command surface

```
plot line|scatter|bar|histogram|step|impulses   # build spec; render inline
plot data   put|get|list|rm
plot panel  list|show|render
plot rig    up|down|status|display
```

## Deferred (explicitly not in this plan)

polars/parquet; timer-based refresh; interactivity (zoom/brush); multi-session
dashboards; a bespoke notebook file format.

## Decisions (G1, agreed)

- **D1 ACCEPTED** — dashboard is one `.nu` file listing panels.
- **D2 DECIDED: manual refresh.** No watcher, no hash-skip machinery, no
  dependency tracking. Redraw on request. (The content hash stays in the store
  meta as cheap bookkeeping, but nothing acts on it yet.)
- **D3 DECIDED: one zellij pane per panel**, arranged by a KDL layout —
  *not* a single pane drawing its own grid. zellij handles layout and resize.
- **D4 pending** — clarified: should `plot line` auto-render inline at the REPL
  (returning nothing) and expose the spec via `--spec` for panel use?
  Proposed: yes, always on, no env gate.
- **D5 pending probe Q9** — does a pane resize leave the chart blurry (rescaled
  pixels)? If yes, the render plane needs a resize hook to re-render at the new
  size. More pressing now that D3 makes panels ordinary resizable zellij panes.
- **D6 open (Phase 5)** — how a manual refresh reaches N panel panes.
