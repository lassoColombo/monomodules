# Phase 0 — findings

Environment: zellij **0.45.0** (brew), Ghostty, chafa 1.18.2, vl-convert 1.9.0, nu 0.115.1.

## 0.1 KGP capability — CONFIRMED

Probed with a real tty via `zellij action new-pane`. Replies:

| query | reply | meaning |
|---|---|---|
| `ESC[c` (DA1) | `ESC[?62;4;52c` | VT220 + sixel(4) + ANSI colors(52) |
| `ESC[16t` cell px | `ESC[6;53;20t` | cell = **20w × 53h** px |
| `ESC[14t` text area px | `ESC[4;1855;3000t` | **3000×1855** px |
| `ESC_Gi=31,a=q...` | `ESC_Gi=31;OK ESC\` | **KGP SUPPORTED** |

### Sizing gotcha (important)
The pixel queries describe the **outer Ghostty window, not the zellij pane**.
Text area 3000×1855 / cell 20×53 = 150×35 cells, but the probing pane was 88×11.

=> Panel image size must be computed:
   `px_w = pane_cols * cell_w`, `px_h = pane_rows * cell_h`
   with pane dims from nushell (`term size`) and cell dims from `ESC[16t`.
   Never trust `ESC[14t` for pane geometry.

## 0.2 Latency budget — vl-convert is FAST ENOUGH

| rows | gen | serialize | vl-convert | total |
|---|---|---|---|---|
| 1k | 1.5ms | 1.0ms | 468ms | ~470ms |
| 20k | 17ms | 9ms | 364ms | ~390ms |
| 100k | 84ms | 46ms | 629ms | ~760ms |

Sub-second at 100k rows => **on-change reactivity is affordable**; Vega-Lite stays
as the chart backend (decision 1 confirmed empirically, not assumed).
Cost is dominated by vl-convert itself, roughly flat in row count -- so the
render plane, not the data plane, is the thing to cache.

## 0.3 zellij control surface

- `zellij pipe` is **plugin-only** (needs a wasm plugin) -> not the control path.
- `zellij action` is the practical control path. Useful verbs:
  - `new-pane --floating --x --y --width --height --name` -> panel geometry
  - `new-pane --in-place --pane-id <id>` -> replace a pane's contents
  - `--close-on-exit`, `--blocking`
  - returns the created pane id (`terminal_<n>`) on stdout -> addressable panels
  - `dump-screen`, `dump-layout`, `rename-pane`, `focus-pane-id`
- Floating panes with explicit geometry are a strong candidate for display panels.

## Harness gotchas (cost real time; don't repeat)
- `zellij action new-pane` **inherits the caller's env** -> got `TERM=dumb` from the
  agent toolchain. Force `TERM` in probe scripts.
- macOS ships **bash 3.2**, which has **no fractional `read -t`**. `read -t 0.3`
  errors out, silently truncating escape replies to 1 byte and leaving the rest
  queued (which then bleeds into the next query's reply). Use
  `stty raw -echo min 0 time <tenths>` + `head -c N < /dev/tty` instead.
- Drain the tty between queries or replies bleed across.

## 0.1b KGP behaviour — visual probe (user-run, 2026-08-23)

| Q | result |
|---|---|
| Q1 render at all | **yes** |
| Q2 same id, new image | old image **destroyed**, new one drawn **at the cursor** -> leaves a hole |
| Q3 delete by id (`a=d,d=i`) | **works**; frees the pixels, cells stay blank, text does **not** reflow |
| Q4 chafa vs raw KGP | visually equivalent |
| Q5 pane resize | **images resize with the pane** |
| Q6 scroll | **images scroll with the text** |

### Consequences

1. **Images are cell-anchored, not screen-anchored** (Q5+Q6). zellij tracks them as
   content in the grid. => the notebook horizon (plots in scrollback) and the
   dashboard horizon (plots pinned in panels) can share **ONE render path**.
   This collapses a whole branch of the design.

2. **Id reuse is destroy+redraw, not replace-in-place** (Q2). The new image lands
   at the cursor, wherever that is. So the render plane must own **explicit cursor
   positioning** (CUP `ESC[<row>;<col>H`) around every transmit. Sequence for a
   panel refresh is: save cursor -> move to panel origin -> delete old id ->
   transmit new -> restore cursor.

3. **Deleting does not reflow** (Q3) -- correct for a dashboard (slots keep their
   geometry) and the reason a panel must be redrawn at a known origin.

4. Raw KGP is preferred over chafa (Q4): same output, but we already need id and
   placement control that chafa does not expose. One less dependency.

### Still unverified (probe C)
- cursor-positioned delete+redraw giving *clean* in-place replacement
- several simultaneous images, updating one without disturbing the others
- whether resize rescales the *existing* pixels (blurry) or forces a redraw
  -> if it rescales, the control plane needs a resize hook to re-render at the
     new pixel size

## Test-harness gotchas (nutest)

- **A test name containing an apostrophe breaks the WHOLE suite.** nutest builds
  a command list embedding each test name as a bare token, so `"the table's
  columns"` produces an unclosed-quote parse error that fails every test in the
  file — with an error that points at generated code, not at your test. Keep
  apostrophes out of test names.
- `term size` reports **80x24** under nutest, not `0x0`. Any test asserting on
  terminal-derived geometry must assert invariants, not literal numbers.
- Chart commands write the completion cache as a side effect, so tests must
  redirect `$env.PLOT_STATE` (see `tests/support.nu isolated`) or they race each
  other and clobber the real cache.
