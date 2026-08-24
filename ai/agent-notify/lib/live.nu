# Pane-existence liveness for GC. Returns the set of live "<session>|<pane_id>"
# keys across all non-EXITED sessions, or null if zellij is unavailable — the
# caller MUST treat null as "don't prune" (never wipe records blindly).
#
# This is the ONLY scan in the module, and it runs solely from `reconcile` (the
# slow janitor), never on the event render path. It reuses zellij.nu's
# `real-panes` so "a real pane" is defined in exactly one place.
#
# All-or-nothing on purpose: one unreadable session yields null for the whole
# set. A partial answer would mark that session's every agent dead, and the GC
# would drop live records and strip their tabs.

use zellij.nu *

export def live-keys [] {
    let r = try { ^zellij list-sessions -n | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) { return null }
    let sessions = $r.stdout
        | lines
        | where {|l| not ($l | str contains "EXITED") }
        | each {|l| $l | str trim | split row ' ' | first }
        | where {|s| $s != "" }

    mut keys = []
    for s in $sessions {
        let panes = real-panes $s
        if ($panes == null) { return null }
        $keys = ($keys | append ($panes | each {|p| $"($s)|($p.id)" }))
    }
    $keys
}
