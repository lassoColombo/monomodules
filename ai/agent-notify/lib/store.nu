# On-disk agent-state store: one JSON file per agent instance, keyed by
# (session, pane_id). Per-agent files mean concurrent agents never race on a
# shared file — each hook writes only its own. Readers glob + merge.
#
# Record schema:
#   { session, pane_id, tab_id, tab_position, tab_name, pane_name, pane_locked, agent,
#     transcript, state, preview, preview_md }
# preview is the message flattened to plain text (the bar), preview_md the same
# message as the agent wrote it (the picker renders it). See lib/markdown.nu.
# state ∈ working | awaiting | needs-attention | idle.
#
# This module is pure state — it never touches zellij or SketchyBar. Liveness GC
# and title projection live in mod.nu; the frontend poke lives in the hook glue.

use paths.nu *

def record-file [session: string, pane_id: int] {
    let safe = $session | str replace --all '/' '_'
    [(store-dir) $"($safe).($pane_id).json"] | path join
}

# This agent's record, or null.
export def get [session: string, pane_id: int] {
    let f = record-file $session $pane_id
    if ($f | path exists) { try { open $f } catch { null } } else { null }
}

# Upsert this agent's record. Atomic (temp + rename) so cross-file readers
# (tab aggregation, list) never observe a half-written record.
export def put [rec: record] {
    ensure-dir (store-dir)
    let f = record-file $rec.session $rec.pane_id
    let tmp = $"($f).tmp"
    $rec | to json | save --force $tmp
    mv --force $tmp $f
}

# Remove this agent's record (session end / clear / GC).
export def drop [session: string, pane_id: int] {
    let f = record-file $session $pane_id
    if ($f | path exists) { rm --force $f }
}

# All records. No liveness filtering here — trust the store (normal exits drop
# their record); GC of abruptly-killed panes is `reconcile`'s job (mod.nu).
export def list [] {
    let dir = store-dir
    if not ($dir | path exists) { return [] }
    glob ($dir | path join "*.json") | each {|f| try { open $f } catch { null } } | compact
}
