# Reflects AI-agent state in the zellij pane/tab titles, and projects those
# titles onto a cross-session SketchyBar popup. Submodule of `ai`; commands are
# `ai agent-notify <cmd>`.
#
#  - Pane: "<sym> <base>" — a SMALL state indicator prefixed to the pane name
#          (only while an agent is in a state; idle panes are just their name).
#  - Tab:  a bare AGGREGATE over every agent pane in the tab ("▴ •2 <base>").
#
# There is ONE source of truth: the live pane titles (see lib/zellij.nu `scan`).
# They die with the pane, so a killed agent leaves nothing stale behind — no
# separate state store. The tab title and the SketchyBar popup are both
# projections of that scan, recomputed by `reap` (run on a heartbeat so an
# abruptly-closed pane self-heals). No-op outside zellij ($ZELLIJ_PANE_ID).

use lib/const.nu *
use lib/title.nu *
use lib/zellij.nu *
export use jump.nu *
export use sketchybar.nu *

def pane-of [panes: table, id: int] { $panes | where id == $id | get -o 0 }

def my-pane-id [] {
    if ($env.ZELLIJ? | is-empty) { return null }
    let s = $env.ZELLIJ_PANE_ID? | default ""
    if ($s | is-empty) { return null }
    $s | into int
}

# Recompute one tab's bare aggregate from its live panes and rename it — only if
# it changed, so idle reaps cause no churn. No agents → bare base name.
export def reconcile-tab [session: string, tab_id: int, panes: table] {
    let tp = $panes | where session == $session and tab_id == $tab_id
    if ($tp | is-empty) { return }
    let current = $tp | first | get tab_name
    let base = (parse-title $current).base
    let folded = fold-symbols ($tp | each {|p| (parse-title $p.title).symbol })
    let desired = bare-title $folded $base
    if $desired != $current { rename-tab $session $tab_id $desired }
}

# Reconcile every tab that currently holds panes, across all sessions.
export def reconcile-tabs [panes: table] {
    $panes | select session tab_id | uniq | each {|st|
        reconcile-tab $st.session $st.tab_id $panes
    } | ignore
}

# The heartbeat: re-derive both surfaces from one live scan, self-healing staleness.
export def reap [] {
    let panes = scan
    reconcile-tabs $panes
    render-popup $panes
}

# Core: set this pane's small indicator + name, recompute the tab aggregate.
# `name` overrides the pane base; `drop_prefix` removes the indicator (for `clear`).
def render [agent: string, symbol: string, name?: any, drop_prefix = false] {
    let pane_id = my-pane-id
    if $pane_id == null { return }
    let session = $env.ZELLIJ_SESSION_NAME? | default ""
    if ($session | is-empty) { return }
    let panes = session-panes $session
    let me = pane-of $panes $pane_id
    if $me == null { return }

    # Pane: "<sym> base" — small indicator prefixed to the name.
    let pane_base = if ($name | is-empty) { (parse-title $me.title).base } else { $name }
    let pane_sym = if $drop_prefix { "" } else { $symbol }
    let pane_title = bare-title $pane_sym $pane_base

    # Idempotent: unchanged title → my tab contribution is unchanged too, so skip
    # the rename/reconcile/poke. Keeps the per-tool PostToolUse hook near-free; the
    # heartbeat still self-heals cross-pane staleness.
    if $pane_title == $me.title { return }
    rename-pane $session $pane_id $pane_title

    # Tab: reconcile from the live panes, with my just-set title patched in (a
    # fresh list-panes might not reflect the rename yet).
    let panes = $panes | each {|p| if $p.id == $pane_id { $p | update title $pane_title } else { $p } }
    reconcile-tab $session $me.tab_id $panes

    poke   # nudge the popup; the heartbeat is the safety net.
}

# SessionStart: set the pane's name (no indicator yet — nothing pending).
export def session-start [agent: string, name?: string] {
    render $agent "" $name
}

# "▴ base" — agent is blocked, needs user attention.
export def needs-attention [agent: string] { render $agent $S_NEED }

# "◦ base" — agent is actively working.
export def working [agent: string] { render $agent $S_WORK }

# "• base" — agent returned control, your turn.
export def awaiting [agent: string] { render $agent $S_WAIT }

# Remove this pane's indicator; recompute the tab aggregate over the rest.
export def clear [] { render "" "" null true }
