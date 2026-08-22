# On-disk agent-state store: one JSON file per agent instance, keyed by
# (session, pane_id). Per-agent files mean concurrent agents never race on a
# shared file — each writes only its own. Readers glob + merge.
#
# Record schema:
#   { session, pane_id, tab_position, tab_name, agent, state, base, updated_at }
# where state ∈ working | awaiting | needs-attention | idle.
# "Notifications" are simply the records whose state is awaiting | needs-attention.

use paths.nu *

def record-file [session: string, pane_id: int] {
    let safe = $session | str replace --all '/' '_'
    [(store-dir) $"($safe).($pane_id).json"] | path join
}

# Nudge the frontend (SketchyBar) to re-read the store. No-op if not installed.
export def store-poke [] {
    try { ^sketchybar --trigger agent_notify_update | complete | ignore }
}

# Upsert this agent's record.
export def store-put [rec: record] {
    ensure-dir (store-dir)
    $rec | to json | save --force (record-file $rec.session $rec.pane_id)
    store-poke
}

# Remove this agent's record (session end / clear).
export def store-drop [session: string, pane_id: int] {
    let f = record-file $session $pane_id
    if ($f | path exists) { rm --force $f }
    store-poke
}

# All records, pruned of dead sessions first.
export def store-list [] {
    store-prune
    let dir = store-dir
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.json") | each {|f| try { open $f } catch { null } } | compact
}

# Delete records whose session is no longer alive (exited or gone).
export def store-prune [] {
    let alive = try {
        ^zellij list-sessions -n
        | lines
        | where {|l| not ($l | str contains "EXITED") }
        | each {|l| $l | str trim | split row ' ' | first }
        | where {|s| $s != "" }
    } catch { null }
    if $alive == null { return }   # zellij unavailable — don't prune blindly
    let dir = store-dir
    if not ($dir | path exists) { return }
    for f in (glob ($dir | path join "*.json")) {
        let rec = try { open $f } catch { null }
        if $rec == null { continue }
        if ($rec.session not-in $alive) { rm --force $f }
    }
}
