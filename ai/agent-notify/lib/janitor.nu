# The liveness janitor. Records are dropped by SessionEnd, so the only leaks are
# panes killed abruptly; this is the one place zellij is scanned, and it runs on
# a slow cadence from whichever surface polls (the bar's 30s timer, the picker
# before it offers a list) — never on the hook path.

use store.nu
use live.nu
use project.nu *

# GC records whose pane died abruptly, fixing their tabs, then return the
# survivors. No-op prune if zellij is unavailable.
export def gc [] {
    let recs = store list
    let live = live live-keys
    if ($live == null) { return $recs }
    let dead = $recs | where {|r| ($"($r.session)|($r.pane_id)") not-in $live }
    if ($dead | is-empty) { return $recs }
    for d in $dead { store drop $d.session $d.pane_id }
    let survivors = $recs | where {|r| ($"($r.session)|($r.pane_id)") in $live }
    # Recompute every tab that lost an agent (from the survivors that remain).
    $dead | where {|d| $d.tab_id? != null } | select session tab_id | uniq | each {|t|
        project-tab $t.session $t.tab_id $survivors null
    } | ignore
    $survivors
}
