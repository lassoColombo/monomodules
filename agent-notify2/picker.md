# The v2 picker — research, findings, and the design to build

**Written 2026-09-12, at the end of a research session.** Everything here was
measured or run on this machine; nothing is recalled from documentation. The
prototype in §7 ran, and its screenshots in §6 are real `dump-screen` output.

Read this instead of re-deriving it. §3 and §4 are the expensive parts.

---

## 0. Why this file exists

`agent-notify2 browse` currently works, and is **wrong**. It depends on `sk`
(nu_plugin_skim) and on `bat`. Both were rejected:

> "bat should not even be mentioned. that was my choice and will not be present
> as a dependency in the final result. for now we will simply display the
> markdown of the agent as is. another thing is sk: opinionated choice that must
> be removed."

The replacement is to be built in a dedicated max-effort session, starting here.

---

## 1. The constraints

1. **No external dependency at all.** Not skim, not bat, not pandoc.
2. **Nushell's own input facilities**, and zellij. Nothing else.
3. **Heavily rely on zellij capabilities** to build the picker and its preview.
4. **No configuration surface for the picker.** No `$env.<module>_config.picker`
   hook, no settings. (plan.md D48 says "skim is a hard dependency" — that
   decision is now WRONG and must be revised when this is built.)
5. **Resilient.** A design that can break silently was explicitly rejected —
   see §5, design R.

---

## 2. What exists today, and what must go

| file | state |
|---|---|
| `integrations/zellij/browse.nu` | **to be replaced.** skim + bat + `require-picker` + `pane`/`KEYS` sizing |
| `tests/browse.nu` | 25 assertions; `rows`/`preview` shapes will change, ordering and label rules survive |
| `mod.nu` | `export use integrations/zellij/browse.nu` — stays |
| `~/.config/zellij/config.kdl` | Alt-a runs the skim version; **must be re-flipped**, backup `config.kdl.bak-picker-*` |
| `plan.md` D48 | "picker has NO configurable engine — skim is a dependency" → **REVISE**: no engine at all |
| `browse wiring` | prints a binding that passes `--plugins <nu_plugin_skim>`; that goes |

**`integrations/zellij/jump.nu` is DONE and good.** Do not touch it. The picker's
last line is `jump $picked.rec.id`. Its three zellij gotchas are recorded in
plan.md §11 and its own header.

What survives from the current `browse.nu`, conceptually:

- urgency order `["needs-attention" "awaiting" "working" "idle"]`, idle last and
  not hidden
- label rule: `name` → `cwd | path basename` → first 8 of the id
- the three glyphs as `\u{...}` escapes (PUA characters do not survive tooling)
- ANSI **names** for colour, not hex — a terminal has a theme and this surface
  should obey it

---

## 3. Capability inventory (all verified on this machine)

### 3.1 nushell `input list`

Far more capable than v1's era. **Renders a list of records as an aligned table**
with headers, drawn by nushell:

```
agent
  pane │  state   │        agent        │    where
───────┼──────────┼─────────────────────┼─────────────
> 73   │ awaiting │ zz                  │ home/.config
  3    │ working  │ bar-drawers-preview │ home/root
[1-2 of 2]
```

- flags: `--multi --fuzzy --index --no-footer --no-separator --case-sensitive`
  `--display <cell-path|closure> --no-table --per-column`
- `--display` **disables table mode**
- `--fuzzy` adds a query line that ALSO begins with `> `
- colours come from `$env.config.color_config`; table characters from
  `$env.config.table.mode`
- returns the original record; `null` on Esc / `q` / Ctrl-C
- **it is OPAQUE**: it blocks and emits nothing until Enter. There is no hook on
  "the highlight moved". This single fact drives the whole design.

### 3.2 nushell `input listen`

```
> input listen --types [key] --timeout 2sec
{type: key, key_type: "other", code: "down", modifiers: []}
```

Verified inside a zellij pane, keys delivered by `zellij action send-keys`:

```
other/down   other/up   other/enter   other/esc   char/j
```

- types: `focus key mouse paste resize`
- `key_type`: `char` (letters/symbols), `other` (up, down, enter, esc,
  backspace…), `f`, `media`
- `modifiers`: `shift control alt super hyper meta`
- `--raw` adds numeric codes
- **`--timeout` THROWS on expiry**, it does not return null. Needs
  `try { input listen … } catch { null }`. This cost time to find.
- blocks until a key arrives; no polling, no latency of its own

### 3.3 zellij

Four capabilities v1 never used, and they are what makes a zellij-native picker
possible:

| command | what it gives |
|---|---|
| `action dump-screen --pane-id <id>` | **reads ANY pane's screen** to stdout. `--full` for scrollback, `--ansi` to keep styling, `--path` to a file |
| `action send-keys --pane-id <id> <keys>` | drives any pane's keyboard **without focusing it** |
| `action write-chars --pane-id <id> <chars>` | types text into any pane |
| `run --floating -x -y --width --height --name` | creates a pane at exact coordinates, prints `terminal_<N>` on stdout |
| `action change-floating-pane-coordinates --pane-id -x -y --width --height --pinned` | a pane can **move and resize itself** |

Also present and possibly useful: `action list-panes -j` (JSON with `is_focused`,
`is_floating`, `exited`, geometry), `action stack-panes`, `action close-pane`
(focused pane only), `action toggle-pane-pinned`, `action set-pane-color`,
`run --in-place`, `run --blocking`, `attach -b` (create a detached session).

**Measured:** `dump-screen` round trip = **12ms**.

**What a `dump-screen` of a Claude pane actually contains** — this is the payoff:

```
⏺ Committed as 7fd6289.
  Used git commit with the staged index only, not -a — so the other session's…
✻ Brewed for 27s · 1 shell still running
❯ apply the same refactor to telescope
  N │ Opus 5 (1M context) │ effort high │ ctx ━━╌╌╌╌╌╌╌╌╌╌ 8% │ …
```

The agent's **real screen**, live. This deletes `bat`, the markdown rendering,
and the picker's use of the `message` field in one stroke. The store's `message`
stays for the BAR's drawer preview; the picker does not need it except as a
fallback for an agent with no pane.

---

## 4. Findings that cost time

1. **`input listen --timeout` throws.** (§3.2)
2. **`zellij run` STEALS FOCUS.** After creating a pane you must
   `focus-pane-id` back, and a `sleep 300ms` afterwards was needed before
   `input list` would behave. Two-pane designs all pay this.
3. **`dump-screen` returns empty for a pane that has not rendered yet.** Several
   early probes looked like failures and were just races. Wait ~1.5s after
   creating a pane before trusting a dump.
4. **Testing `[ -t 1 ]` inside a block redirected to a file** reports "not a tty"
   — my own bug. A `zellij run` pane gives a real TTY on both streams.
5. **`input list` renders fine in a `zellij run` pane**, and `dump-screen`
   captures it, marker and all.
6. **`zellij action switch-session` CREATES a session it cannot find.** Probing
   it left an orphan `nope` server running. Already recorded in plan.md §11 and
   handled in `jump.nu`. `zellij delete-session <name> --force` removes it.
   `zellij action list-clients` is the only way to tell whether a session is
   being *looked at* — `ps` cannot, because a client's argv still says
   `zellij attach <original>` after it has switched.
7. **skim cannot run without a terminal**: `Operation not supported on socket
   (os error 102)`. Any picker test needs a real pane. The way to get one:
   `zellij run --floating … -- nu -n /tmp/probe.nu`, then `dump-screen` it and
   `send-keys` at it. **This is the technique that made all of this testable** —
   keep using it.

---

## 5. Designs considered

### R — `input list` + a preview pane that scrapes the picker's screen  ❌ REJECTED

A second pane polls `dump-screen --pane-id <picker>`, finds the line starting
with `> `, reads the pane id out of column one, and dumps that agent's screen.

**It was built and it worked.** Two floating panes, the preview followed the
highlight correctly. Rejected anyway, by the user: *"this does not seem a
resilient solution."* Correct — it depends on nushell's `> ` marker, on the `│`
separator, on a polling interval, and on `zellij run` focus timing. It fails
**silently**.

Recorded because the mechanism is proven and might be wanted for something else.

### A — two steps: `input list` → full-screen preview → jump or back

List, Enter, see the whole screen in the pane, then a second `input list` for
`jump` / `back`. ~40 lines. Nothing to parse, poll or coordinate. Costs one
keypress and loses your place on the way back.

### B — one preview pane showing EVERY agent at once, built once

No polling, no parsing; static for the life of the picker. Good for 2–4 agents,
cramped beyond that. Costs 12ms × agents at startup.

### C — own the event loop with `input listen`  ✅ RECOMMENDED

One pane. We draw the list and the preview and handle the keys, so **we know the
highlight because we set it**. Prototyped and working — §6, §7.

---

## 6. The recommended design (C)

### What it looks like — real `dump-screen` output from the prototype

```
agents  ▸ █
──────────────────────────────────────────────────────────────────────────────
▌  awaiting  zz                   home/.config
   working   bar-drawers-preview  home/root
──────────────────────────────────────────────────────────────────────────────
⏺ Background command "Test whether closures in env…" was stopped
⏺ Noted — that's a background command from the other session in this repo…
  Nothing for me to act on; the zz refactor is committed at 7fd6289.
↑↓ move · enter jump · esc cancel · type to filter
```

Press ↓ — the preview follows, and is now the other agent's live screen:

```
   awaiting  zz                   home/.config
▌  working   bar-drawers-preview  home/root
──────────────────────────────────────────────────────────────────────────────
     p='/tmp/pick.nu'
     s=open(p).read()
     s=s.replace(' $sel = [[$sel 0] | math max, …
```

Type `zz` — it filters and the columns re-pad:

```
agents  ▸ zz█
──────────────────────────────────────────────────────────────────────────────
▌  awaiting  zz    home/.config
──────────────────────────────────────────────────────────────────────────────
  Nothing pending from me; the only next action is yours…
```

### Why it is resilient — three absences

- **Nothing to parse.** We set `sel`, so we know it.
- **Nothing to poll.** `input listen` blocks until a key arrives.
- **Nothing to coordinate.** One pane, one process. No second pane, no focus
  juggling, no orphan panes, no timing.

A **vertical stack** (list above, preview below) also means no cursor
addressing: `clear`, then print lines in order. It matches the stated preference
that a preview belongs *under* the list.

### Two details that earn their place

- **The heartbeat.** `--timeout 2sec` turns a quiet moment into a redraw, so the
  preview stays LIVE while you sit still — you watch an agent working.
- **The preview is `dump-screen`** — the agent's real terminal. Fall back to the
  stored `message`, as raw markdown, for an agent with no pane.

---

## 7. The prototype — verified working, 91 lines

Not production code. It has no scrolling test, does not re-read the store on the
heartbeat, and its comments are thin. It is here because it RAN.

```nu
use /Users/colombos/projects/personal/nushell/monomodules/agent-notify2

const GLYPH = {working: "\u{f021}", awaiting: "\u{f075}", needs-attention: "\u{f071}", idle: " "}
const URGENCY = ["needs-attention" "awaiting" "working" "idle"]
const HOME = "\u{1b}[H\u{1b}[J"        # cursor home, clear to end
const HIDE = "\u{1b}[?25l"
const SHOW = "\u{1b}[?25h"

def hue [s: string] {
    match $s {
        "needs-attention" => (ansi light_red_bold), "awaiting" => (ansi yellow_bold)
        "working" => (ansi cyan), _ => (ansi dark_gray)
    }
}

def load [] {
    agent-notify2 store list
    | each {|r| {
        state: ($r.state? | default "idle")
        name: ($r.name? | default ($r.cwd? | default "" | path basename))
        place: $"($r.zellij?.session? | default '-')/($r.zellij?.tab_base? | default '-')"
        pane: ($r.zellij?.pane_id? | default "")
        rec: $r
    }}
    | sort-by {|c| $URGENCY | enumerate | where item == $c.state | get -o 0.index | default 9 } {|c| $c.name }
}

def screen-of [pane: string, lines: int] {
    if ($pane | is-empty) { return [$"(ansi dark_gray)not in a zellij pane(ansi reset)"] }
    let d = (^zellij action dump-screen --pane-id $"terminal_($pane)" | complete)
    let body = $d.stdout | lines | where {|l| ($l | str trim) != "" }
    if ($body | is-empty) { [$"(ansi dark_gray)nothing on screen(ansi reset)"] } else { $body | last $lines }
}

def draw [rows: list, sel: int, query: string, top: int, size: record] {
    let list_h = [([($rows | length) 1] | math max) (($size.rows - 6) // 2)] | math min
    let pv_h = $size.rows - $list_h - 5
    let w = $size.columns
    let w_state = $rows | each {|c| $c.state | str length } | append 7 | math max
    let w_name = $rows | each {|c| $c.name | str length } | append 4 | math max

    mut out = [$"(ansi cyan_bold)agents(ansi reset)  (ansi dark_gray)▸(ansi reset) ($query)(ansi dark_gray)█(ansi reset)"]
    $out = $out ++ [$"(ansi dark_gray)(1..$w | each {|| '─' } | str join)(ansi reset)"]
    for i in $top..<([($top + $list_h) ($rows | length)] | math min) {
        let c = $rows | get $i
        let on = $i == $sel
        let bar = if $on { $"(ansi cyan)▌(ansi reset)" } else { " " }
        let g = $GLYPH | get -o $c.state | default " "
        let body = $"(hue $c.state)($g) ($c.state | fill --width $w_state)(ansi reset)  ($c.name | fill --width $w_name)  (ansi dark_gray)($c.place)(ansi reset)"
        $out = $out ++ [$"($bar) (if $on { $"(ansi white_bold)" } else { "" })($body)"]
    }
    if ($rows | is-empty) { $out = $out ++ [$"  (ansi dark_gray)no agent matches(ansi reset)"] }
    $out = $out ++ [$"(ansi dark_gray)(1..$w | each {|| '─' } | str join)(ansi reset)"]
    let pv = if ($rows | is-empty) { [] } else { screen-of ($rows | get $sel | get pane) $pv_h }
    $out = $out ++ ($pv | each {|l| $l | str substring 0..($w - 1) })
    $out = $out ++ [$"(ansi dark_gray)↑↓ move · enter jump · esc cancel · type to filter(ansi reset)"]
    print -n ($HOME + ($out | str join "\r\n"))
}

def main [] {
    let all = load
    mut sel = 0
    mut query = ""
    mut top = 0
    print -n $HIDE
    loop {
        let size = (term size)
        let q = $query | str downcase
        let rows = if ($q | is-empty) { $all } else {
            $all | where {|c| ($"($c.state) ($c.name) ($c.place)" | str downcase | str contains $q) }
        }
        if $sel >= ($rows | length) { $sel = ([0 (($rows | length) - 1)] | math max) }
        let list_h = [([($rows | length) 1] | math max) (($size.rows - 6) // 2)] | math min
        if $sel < $top { $top = $sel }
        if $sel >= ($top + $list_h) { $top = $sel - $list_h + 1 }
        draw $rows $sel $query $top $size

        # A timeout THROWS rather than returning null — so a quiet second is a
        # redraw, which is what keeps the preview live while you sit still.
        let ev = try { input listen --types [key] --timeout 2sec } catch { null }
        if $ev == null { continue }
        let code = $ev.code
        let ctrl = "control" in $ev.modifiers
        if ($code == "esc") or ($ctrl and $code == "c") { break }
        if $code == "enter" {
            print -n ($SHOW + $HOME)
            if ($rows | is-empty) { return }
            $"JUMP ($rows | get $sel | get rec.id)\n" | save --force /tmp/pick-result.txt
            return
        }
        if ($code == "down") or ($ctrl and $code == "n") { $sel = $sel + 1 }
        if ($code == "up") or ($ctrl and $code == "p") { $sel = $sel - 1 }
        if $code == "backspace" { $query = ($query | str substring 0..(-2)) ; $sel = 0 }
        if $ev.key_type == "char" and (not $ctrl) { $query = $query + $code ; $sel = 0 }
        let last = ($rows | length) - 1
        if $sel < 0 { $sel = 0 }
        if $sel > $last { $sel = ([$last 0] | math max) }
    }
    print -n ($SHOW + $HOME)
}
```

**Bug found and fixed during prototyping, worth not repeating:** the clamp was
written as `[[$sel 0] | math max, (($rows | length) - 1)] | math min`, which
parses as something else entirely and silently never moved the selection. Two
plain `if`s instead.

---

## 8. Open questions for the build session

1. **Scrolling.** The arithmetic is in the prototype but was never exercised —
   there were only two agents. Needs a test with more rows than fit.
2. **Live list, not just live preview.** The heartbeat currently redraws from a
   store read taken ONCE at startup. Re-reading on the heartbeat makes the list
   itself live (an agent changing state moves in the list while you look at it).
   Cheap — the store is a few small JSON files — but decide deliberately.
3. **Filter semantics.** The prototype does case-insensitive substring over
   `state name place`. Options: add the message, add fuzzy matching (more code),
   or leave it. Substring is predictable, which has value.
4. **Key map.** Currently ↑↓, Ctrl-N/P, Enter, Esc, Ctrl-C, Backspace, and any
   character types into the filter. Consider: Ctrl-U to clear, Home/End,
   PageUp/PageDown, Tab.
5. **Preview for an agent with no pane.** Fall back to the stored `message` as
   raw markdown. Confirm that is wanted.
6. **What the row carries.** state, name, place today. The live preview makes a
   message column less necessary, but it is what lets you filter on something an
   agent said.
7. **Resize.** `input listen --types [key resize]` would catch a pane resize and
   redraw. The heartbeat already covers it within 2s; a resize event makes it
   instant.
8. **Terminal state on crash.** `HIDE` hides the cursor. If the script dies
   between `HIDE` and `SHOW` the cursor stays hidden in that pane. The pane is
   closed by `close_on_exit` so it probably does not matter — confirm.
9. **How to test it.** Pure functions (`load`, row building, filtering, the
   draw-to-list-of-strings) can be asserted exactly. The loop cannot. Consider
   making `draw` return a list of lines rather than printing, so the whole frame
   is assertable — that is the same data-first split as `zellij commands` and
   `sketchybar message`, and it is how every other side effect in this module is
   tested.
10. **Keybinding.** `config.kdl` Alt-a must lose `--plugins <nu_plugin_skim>`.
    The block becomes plain `nu -n -c "use <root>; agent-notify2 browse"`.
    `browse wiring` prints it.

---

## 9. What "done" looks like

- `integrations/zellij/browse.nu` rewritten: no `sk`, no `bat`, no
  `require-picker`, no `$env` hook, no settings.
- `draw` returns lines; a suite asserts frames exactly, the way
  `tests/sketchybar.nu` asserts messages.
- `tests/browse.nu` rewritten around that.
- plan.md: D48 revised, a new decision for "we own the event loop and why",
  §11 gains the zellij and nushell facts from §3 and §4 here.
- `config.kdl` re-flipped; `browse wiring` matches it.
- The whole suite green, and the hook still ~30ms — the picker must stay OUT of
  the hot import cone (`integrations/zellij/browse.nu` is reached only through
  the facade, never through `clients/claude.nu`).
