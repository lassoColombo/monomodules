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
# NAMING — `read` rather than the obvious `get`: a def named after
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

def read-dir [dir: string]: nothing -> list<any> {
    if not ($dir | path exists) { return [] }
    # `ls` on a glob that matches nothing is an ERROR, not an empty list, and a
    # store whose last agent has just ended is exactly that case — the directory
    # outlives its contents. Found by the Codex suite, which drops its only record
    # and then reads the store; every surface would have hit it eventually.
    let files = try { ls ($"($dir)/*.json" | into glob) } catch { [] }
    $files
    | each {|f| try { open --raw $f.name | from json } catch { null } }
    | compact
}

# Every LIVE record, and only those. No liveness filtering beyond that — proving
# an agent dead is the janitor's job, and doing it here would make every read pay
# for a `ps`.
#
# This is the read the whole hot path hangs off, which is why an ended session is
# in another directory rather than behind a flag here (core/paths.nu).
export def list []: nothing -> list<any> { read-dir (agents-dir) }

# Sessions that have ended and not yet been reaped. Nothing on the hot path reads
# this; it is here so `agent-notify store list --ended` can, and so a future
# "resume a recent session" has somewhere to look.
export def ended []: nothing -> list<any> { read-dir (ended-dir) }

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

# ── ending, and coming back ──────────────────────────────────────────────────
#
# A SESSION IS NOT DESTROYED WHEN IT STOPS RUNNING. Claude Code does not destroy
# one — `--resume` hands back the SAME id, and `--fork-session` exists to opt out
# of that. zellij does not destroy a session when you detach. tmux does not.
# Every one of them says the same thing: the session is the durable object, and
# running is a state it is in.
#
# This module used to disagree, and the visible cost was the NAME. Everything
# else in a record is re-supplied by the next event — `cwd` and `state` by any
# hook, the pane by `observe`, the pid by the walk — but the name is authored,
# once, by a human or by an agent following an instruction, and nothing ever says
# it again. Deleting the record deleted the only copy.

# How long an ended session waits before it is really gone. Long enough to cover
# coming back to something after a weekend, short enough that the directory never
# becomes an archive nobody asked for.
const KEEP_ENDED = 7day

# Reap on ARCHIVE, which is the only moment `ended/` can grow — so it costs once
# per session, never on the hot path, and the clock gains no new job. (On the 30s
# clock it would be 2,880 scans a day to delete something once a week.)
#
# By MTIME, not by a field in the record: `ls` answers without opening anything,
# so scanning 600 files costs 2.5ms where parsing them costs 36.9ms.
def reap []: nothing -> nothing {
    let dir = ended-dir
    if not ($dir | path exists) { return }
    let cutoff = (date now) - $KEEP_ENDED
    let old = try { ls ($"($dir)/*.json" | into glob) | where modified < $cutoff } catch { [] }
    for f in $old { rm --force $f.name }
}

# File this session away. What `SessionEnd` means, and what the janitor does to
# an agent it can prove is gone — the same gesture either way, because a clean
# exit and an abrupt kill leave the same thing behind.
#
# Returns whether there was anything to file, so the caller still learns whether
# the world moved. A plain rename: nothing is read, parsed or rewritten.
export def archive [id: string]: nothing -> bool {
    let f = record-file $id
    if not ($f | path exists) { return false }
    ensure-dir (ended-dir)
    mv --force $f (ended-file $id)
    reap
    true
}

# Take it back out — what a resume is. Called only when a write would CREATE a
# record, because that is exactly when an id we already know can come back.
#
# WHAT RETURNS IS THE SESSION, NOT THE RUN IT WAS IN: the core fields (name, cwd,
# what it last said) and not one namespace. That is `schema durable`, and it is
# the schema's own line rather than a list of exceptions — but it also removes
# the one way this could do harm. A stale `proc` would let the janitor prove the
# resumed session dead and file it away again within 30s; a stale `zellij` would
# rename a pane that has since moved on. Both are facts about a process that has
# exited, and neither outlives it.
export def restore [id: string]: nothing -> bool {
    let f = ended-file $id
    if not ($f | path exists) { return false }
    let rec = try { open --raw $f | from json } catch { null }
    rm --force $f
    if ($rec == null) or (not (is-record $rec)) { return false }
    commit $id (schema durable $rec)
    true
}
