# Projection of the store onto a zellij TAB title: the aggregate marker line a
# tab shows for the agents living in it. Shared by the hook verbs (which project
# after every state change) and the liveness GC (which projects after dropping a
# dead pane), so both compute the same title from the same base name.

use title.nu *
use zellij.nu *
use state.nu *

# A tab's base name: its live title with our markers stripped, else what the
# store still mirrors. A glyph-only or blank live title parses to "" — that is
# our own leftover, not a name, so it must never erase a base we still know.
export def tab-base [live: any, stored: any] {
    let l = parse-title ($live | default "")
    if ($l | is-not-empty) { $l } else { $stored | default "" | str trim }
}

# Recompute one tab's aggregate title from `recs` (the caller's already-loaded
# store list) and rename it — skipping the write when it already equals the live
# title. `current` is that live title when the caller already holds it (the hook
# path); otherwise we look it up, because the tab's BASE NAME lives there and has
# to survive the last agent leaving the tab (`clear`/`gc` pass null).
export def project-tab [session: string, tab_id: int, recs: table, current?: any] {
    let live = if ($current != null) { $current } else { tab-name $session $tab_id }
    if ($live == null) { return }  # tab (or zellij) gone — nothing to project onto
    let tab_recs = $recs | where {|r| ($r.session? == $session) and ($r.tab_id? == $tab_id) }
    let stored = $tab_recs | where {|r| ($r.tab_name? | is-not-empty) } | get -o 0.tab_name
    let glyphs = $tab_recs | each {|r| glyph-of ($r.state? | default "idle") } | where {|g| $g != "" }
    let desired = bare-title (fold-symbols $glyphs) (tab-base $live $stored)
    if ($desired == $live) { return }
    rename-tab $session $tab_id $desired
}
