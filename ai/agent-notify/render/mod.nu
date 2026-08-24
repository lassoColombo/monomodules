# SketchyBar surface for agent-notify: the three counters (working / awaiting /
# needs-attention), their drawers of agent rows, and each drawer's hover preview.
# Commands are `ai agent-notify render <cmd>`, called from thin glue scripts in
# the bar's config:
#
#   scaffold      create the fixed item pool — ONCE, from sketchybarrc
#   (main)        repaint from the store; a NO-OP when the model is unchanged
#   reconcile     GC dead panes, then repaint
#   preview-*     fill / clear a drawer's hover footer
#   alert*        nudge the counter chip on a state change, and drop the nudge
#
# Colours, fonts and layout live in theme.nu / items.nu; the row text, glyphs and
# ordering come from lib/view.nu — shared with the terminal picker (`ai
# agent-notify browse`), so the bar and the picker can never drift apart.
#
# WHY A FIXED POOL: every `--add`/`--remove` costs the SketchyBar daemon ~20ms of
# main-thread relayout+redraw, so tearing the drawers down and rebuilding them
# (~43 items) burned ~0.8 CPU-seconds per paint. Driven both by the fast timer
# AND by the PostToolUse poke (once per tool call, per agent), that pinned the
# daemon near 40% CPU — which is what made bar clicks lag, and made a click that
# opened a drawer get eaten by the rebuild landing right behind it.
#
# So: items are created once and NEVER added/removed again; a paint is pure
# `--set` over a fixed pool of slots (rows past the last agent are drawing=off);
# and a paint whose model matches the last one sends NOTHING at all — the common
# case, since `working` is re-asserted on every single tool call.

use theme.nu *
use items.nu *
use cache.nu
use ../lib/store.nu
use ../lib/janitor.nu *

# The whole bar-side state, derived from the store: per drawer, its agent count
# and the (capped) rows to show. This IS the cache key — if it round-trips
# unchanged, the bar already shows it and the paint is skipped.
def model [recs: list<any>] {
    let flat = sort-agents ($recs | each {|r| {
        state: ($r.state? | default "idle")
        tab_position: ($r.tab_position? | default 0)
        pane_id: $r.pane_id
        session: $r.session
        label: (label $r)
    }})
    drawer-specs | each {|d|
        let rows = $flat | where state == $d.state
        {
            item: $d.item
            n: ($rows | length)
            rows: ($rows | take $ROWS | each {|r| {label: $r.label, session: $r.session, pane_id: $r.pane_id} })
        }
    }
}

# Repaint only what changed; send nothing when nothing did. Only the drawers
# whose slice of the model moved are touched, and only their slots up to
# max(old, new) row count (the rest are already drawing=off).
def paint [recs: list<any>] {
    let now = model $recs
    let now_json = $now | to json --raw
    let prev_json = cache load
    if ($prev_json == $now_json) { return }
    let prev = if ($prev_json == null) { null } else { try { $prev_json | from json } catch { null } }

    mut args = []
    for d in ($now | enumerate) {
        let cur = $d.item
        let old = if ($prev == null) { null } else { $prev | get -o $d.index }
        if ($old != null) and (($old | to json --raw) == ($cur | to json --raw)) { continue }
        let state = drawer-specs | get $d.index | get state
        $args = $args ++ (counter-args $cur.item $state $cur.n) ++ (header-args $cur.item $cur.n)
        # No cache (fresh scaffold) → rewrite every slot, so nothing stale lingers.
        let old_rows = if ($old == null) { $ROWS } else { $old.rows | length }
        let hi = [$old_rows ($cur.rows | length)] | math max
        for j in 0..<$hi {
            let r = $cur.rows | get -o $j
            $args = $args ++ (if ($r == null) { row-off-args $cur.item $j } else { row-args $cur.item $j $r })
        }
        # A changed row set invalidates whatever preview was on screen.
        if ($old == null) or ($old.rows != $cur.rows) { $args = $args ++ (pv-off-args $cur.item) }
    }

    if ($args | is-empty) { cache put $now_json; return }
    # Cache only what the bar actually took, so a dead daemon self-heals.
    if (^$SB ...$args | complete | get exit_code) == 0 { cache put $now_json }
}

# ── Commands ─────────────────────────────────────────────────────────────────

# Instant event refresh — store only, no scan.
export def main [] { paint (store list) }

# Build the item pool. Run once per bar load, from sketchybarrc. Idempotent.
export def scaffold [] {
    for d in (drawer-specs) { ^$SB ...(pool-args $d) | complete | ignore }
    cache clear   # the pool is blank — force the next paint to write everything
}

# Slow janitor — GC abruptly-killed panes, then repaint.
export def reconcile [] { paint (gc) }

# Fill a drawer's preview footer with one agent's message, wrapped over the
# line-item pool (used ones shown, the rest hidden). "—" when there's no message.
export def preview-show [item: string, session: string, pane: string] {
    let rec = store get $session ($pane | into int)
    let text = one-line (if ($rec == null) { "" } else { $rec.preview? | default "" })
    let lines = if ($text | is-empty) { ["—"] } else { wrap-text $text $PV_WIDTH $PV_LINES }
    mut args = []
    for i in 0..<$PV_LINES {
        let line = $lines | get -o $i
        $args = $args ++ (if ($line == null) { ["--set" $"($item).item._pv.($i)" "drawing=off"] } else { pv-line-args $item $i $line })
    }
    ^$SB ...$args | complete | ignore
}

# Hide a drawer's whole preview footer.
export def preview-hide [item: string] {
    ^$SB ...(pv-off-args $item) | complete | ignore
}

# Proactive nudge on a state change: repaint, then — if the agent's stored state
# still matches `state` — wash that drawer's counter chip and flash the drawer
# open, with the alerting pane's row outlined. The list is the normal one; only
# the message footer is left hidden. The glue auto-closes it via `alert-dismiss`.
# The hook fires this unconditionally; the state re-check makes a filtered
# Notification a silent repaint, no nudge.
export def alert [state: string, session: string, pane: string] {
    let pid = $pane | into int
    let recs = store list
    paint $recs
    let rec = store get $session $pid
    if ($rec == null) or (($rec.state? | default "") != $state) { return }
    let item = drawer-of $state
    # Row index = the pane's position within this drawer, per the paint above.
    let idx = model $recs | where item == $item | get -o 0.rows | default []
        | enumerate | where {|e| ($e.item.session == $session) and ($e.item.pane_id == $pid) }
        | get -o 0.index
    # Past the ROWS cap there is no row to point at — the chip alone has to do.
    let row = if ($idx == null) { [] } else { alert-row-args $item $state $idx }
    ^$SB ...((alert-chip-args $item $state) ++ $row) | complete | ignore
}

# Undo the nudge (the timed auto-dismiss): close the popup and drop both
# highlights. Rows are never hidden or relabelled, so no repaint is needed.
export def alert-dismiss [state: string] {
    ^$SB ...(alert-dismiss-args (drawer-of $state)) | complete | ignore
}
