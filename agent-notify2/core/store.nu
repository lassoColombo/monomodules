# The store: the core of the module, and the only thing that owns state.
#
# One JSON file per agent instance, so two agents never contend for a write and
# no lock is needed anywhere; writes are temp-then-rename, so a reader never
# observes half a record. (Both inherited from v1, which got this right.)
#
# This module is PURE STATE. It never touches zellij, SketchyBar, or any surface,
# and it never dispatches: the entry point sequences write-then-project, so that a
# write from the command line projects exactly like a write from a hook, and so
# that this file stays a cheap leaf anything may import — measured at +0.3ms of
# parse against a ~3ms budget for the whole hot path.
#
# `patch` is the operation everything else is built on, and its return value is
# the load-bearing part of the design: it reports whether the world ACTUALLY
# MOVED, comparing only the semantic fields. That one boolean replaces three
# separate mechanisms in v1 — the bash fast-path gate, the `working` verb's early
# return, and the render-side model cache — with a single check in the one place
# able to answer it. When it comes back false the event ends, having cost the
# process floor and one read.
#
# NAMING — `read`/`remove` rather than the obvious `get`/`drop`: a def named after
# a builtin shadows that builtin for every module this one imports, whatever the
# order of the `use` statements, and the failure is a parse error somewhere else
# entirely (`get -o` inside schema.nu, which never mentions our name). Multi-word
# subcommand names are exempt, which is why the COMMAND surface in cli/store.nu
# can still read `store get` — see plan.md §7.

use paths.nu *
use schema.nu

# ── reading ──────────────────────────────────────────────────────────────────

# One agent's record, or null. A malformed file reads as null rather than as an
# error: a surface with one unreadable record should still paint the others.
export def read [id: string]: nothing -> any {
    let f = record-file $id
    if not ($f | path exists) { return null }
    try { open --raw $f | from json } catch { null }
}

# Every record. No liveness filtering — that is the janitor's job, and doing it
# here would make every read pay for a zellij scan.
export def list []: nothing -> list<any> {
    let dir = agents-dir
    if not ($dir | path exists) { return [] }
    ls ($"($dir)/*.json" | into glob)
    | each {|f| try { open --raw $f.name | from json } catch { null } }
    | compact
}

# ── merging ──────────────────────────────────────────────────────────────────

def is-record [v: any]: nothing -> bool { ($v | describe) | str starts-with "record" }

# Merge `changes` into `base`, recursively: a record merges INTO a record, so an
# owner may write one field of its namespace without reading the rest — which is
# what keeps concurrent owners from clobbering each other. Anything else replaces.
#
# A null value DELETES its key. Without it `patch` would be incomplete: a field
# could be written but never removed, and callers would be driven to `set`, which
# replaces everything and reintroduces exactly the read-modify-write races that
# per-record files exist to avoid.
def deep-merge [base: record, changes: record]: nothing -> record {
    mut out = $base
    for k in ($changes | columns) {
        let new = $changes | get $k
        let cur = $out | get -o $k
        $out = if ($new == null) {
            $out | reject --optional $k
        } else if (is-record $new) and (is-record $cur) {
            $out | upsert $k (deep-merge $cur $new)
        } else {
            $out | upsert $k $new
        }
    }
    $out
}

# ── writing ──────────────────────────────────────────────────────────────────

# Commit a fully-formed record. Atomic: a temp file in the same directory (so the
# rename cannot cross a filesystem) replaced over the target in one syscall.
def commit [id: string, rec: record] {
    ensure-dir (agents-dir)
    let f = record-file $id
    let tmp = $"($f).tmp"
    $rec | to json | save --force $tmp
    mv --force $tmp $f
}

# The one write path. Both `patch` and `set` end here, so stamping, validation,
# the change test and the atomic commit happen in exactly one place.
#
# An unchanged write is NOT committed — not for the 0.26ms, but so that
# `changed: false` means precisely "nothing happened", with no mtime moved and no
# file touched. If a heartbeat is ever wanted (an agent proving it is alive
# without changing state), it should be an explicit operation rather than a side
# effect of every no-op write.
def write [id: string, before: any, merged: record]: nothing -> record {
    let final = schema validate (schema stamp $before ($merged | merge {id: $id}))
    let changed = ($before == null) or ((schema semantic $before) != (schema semantic $final))
    if $changed { commit $id $final }
    { changed: $changed, before: $before, after: (if $changed { $final } else { $before }) }
}

# Merge `changes` into this agent's record, creating it when absent. The result is
# what gets validated, which is what lets one code path both create and update.
export def patch [id: string, changes: record]: nothing -> record {
    let before = read $id
    write $id $before (deep-merge ($before | default {}) $changes)
}

# Replace this agent's record wholesale. The escape hatch for the rare case where
# merging is wrong — a client rebuilding its own state from scratch.
export def set [id: string, rec: record]: nothing -> record {
    write $id (read $id) $rec
}

# Forget this agent. Returns whether there was anything to forget.
export def remove [id: string]: nothing -> bool {
    let f = record-file $id
    if not ($f | path exists) { return false }
    rm --force $f
    true
}
