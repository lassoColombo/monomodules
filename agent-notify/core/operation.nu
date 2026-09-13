# The sequence every entry point runs, and the one place displays will be told
# that something happened.
#
# It exists so that the sequence is written once rather than once per client: an
# adapter's whole job is to turn its own native payload into one of the three
# operations below, and this decides what that means. A write typed at the
# command line therefore goes through exactly what a hook goes through — which
# is what keeps the session-store and the displays from ever disagreeing.
#
# THE DISPATCH SEAM is marked below. Step 3 adds `use dispatch.nu` and one call;
# nothing else in the module changes, and no client ever learns that a display
# exists.
#
# An operation is one of:
#
#   {operation-kind: "patch", id, changes, defaults?}
#       merge changes; `defaults` apply only when the record is being created
#   {operation-kind: "set", id, record}
#       replace the record wholesale
#   {operation-kind: "end", id}
#       the agent has stopped running. Its record is FILED AWAY, not destroyed
#       — see core/session-store.nu `end-session`
#   {operation-kind: "ignore", why}
#       nothing to do, and why — so a hook that fires for an event we do not
#       handle is a deliberate no-op rather than a silent one

use session-store.nu
use dispatch.nu

# `defaults` is what lets an adapter say "idle, but only if this is new".
# Claude's SessionStart fires on resume and after compaction as well as at
# startup, and a plain `{state: "idle"}` would knock a working agent back to
# idle every time the context was compacted. Expressing it as a create-only
# default keeps the adapter a pure function of its payload — it never has to
# read the session-store to find out.
def with-defaults [operation: record]: nothing -> record {
    let defaults = $operation.defaults? | default {}
    if ($defaults | is-empty) { return $operation.changes }
    if ((session-store read $operation.id) != null) { return $operation.changes }

    # A write that CREATES is also the moment a resumed session comes back, so
    # it is the one place worth looking in `ended/`. Not a guess: Claude Code
    # hands back the SAME session id on `--resume` (`--fork-session` exists to
    # opt out), so an ended record under this id IS this session.
    #
    # Reopening brings back the core fields and no namespace, so what lands here
    # is a record with a name and a history and nothing about the process that
    # exited. The defaults then still apply — which is right, because a session
    # you have just resumed is idle until you type.
    session-store reopen-session $operation.id | ignore
    $defaults | merge $operation.changes
}

# Apply one operation. Returns the session-store's result, `changed` included,
# so a caller can tell whether anything actually happened.
export def apply [operation: record]: nothing -> record {
    let kind = $operation.operation-kind? | default "ignore"

    let result = match $kind {
        "patch" => (session-store patch $operation.id (with-defaults $operation))
        "set" => (session-store set $operation.id $operation.record)
        "end" => {
            # Read BEFORE filing it away. A display is asked whether its output
            # changes, and it cannot answer that about an agent it never saw.
            # One extra read on the rarest event in the system.
            let before = session-store read $operation.id
            {changed: (session-store end-session $operation.id), before: $before, after: null}
        }
        _ => { {changed: false, before: null, after: null} }
    }

    # ── the displays ──────────────────────────────────────────────────────────
    # Persist first, render after: a repaint that fails must never cost us a
    # fact, and an unchanged write never reaches a display at all. `dispatch` is
    # written so that nothing here can throw — the store has already committed.
    #
    # Dispatch wants the whole session-store BEFORE and AFTER, not our
    # one-record delta, so that a hook and the prune-daemon speak to it the same
    # way. Reconstructing the "before" is our job because only we know which
    # record moved.
    if $result.changed {
        let now = session-store list
        let subject = $result.after | default $result.before | get -o id
        let then = ($now | where id != $subject) ++ (
            if $result.before == null { [] } else { [$result.before] })
        dispatch repaint $then $now | ignore
    }

    $result
}
