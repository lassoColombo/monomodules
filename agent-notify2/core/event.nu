# The sequence every entry point runs, and the one place surfaces will be told
# that something happened.
#
# It exists so that the sequence is written once rather than once per client: an
# adapter's whole job is to turn its own native payload into one of the three
# operations below, and this decides what that means. A write typed at the
# command line therefore goes through exactly what a hook goes through — which is
# what keeps the store and the surfaces from ever disagreeing.
#
# THE DISPATCH SEAM is marked below. Step 3 adds `use dispatch.nu` and one call;
# nothing else in the module changes, and no client ever learns that a surface
# exists.
#
# An operation is one of:
#   {op: "patch", id, changes, defaults?}   merge changes; `defaults` apply only
#                                           when the record is being created
#   {op: "drop",  id}                       forget the agent
#   {op: "ignore", why}                     nothing to do, and why — so a hook
#                                           that fires for an event we do not
#                                           handle is a deliberate no-op rather
#                                           than a silent one

use store.nu

# `defaults` is what lets an adapter say "idle, but only if this is new". Claude's
# SessionStart fires on resume and after compaction as well as at startup, and a
# plain `{state: "idle"}` would knock a working agent back to idle every time the
# context was compacted. Expressing it as a create-only default keeps the adapter
# a pure function of its payload — it never has to read the store to find out.
def with-defaults [op: record]: nothing -> record {
    let defaults = $op.defaults? | default {}
    if ($defaults | is-empty) { return $op.changes }
    if ((store read $op.id) == null) { $defaults | merge $op.changes } else { $op.changes }
}

# Apply one operation. Returns the store's verdict, `changed` included, so a
# caller can tell whether anything actually happened.
export def apply [op: record]: nothing -> record {
    let kind = $op.op? | default "ignore"

    let result = match $kind {
        "patch" => (store patch $op.id (with-defaults $op))
        "drop" => {
            let existed = store remove $op.id
            {changed: $existed, before: null, after: null}
        }
        _ => { {changed: false, before: null, after: null} }
    }

    # ── dispatch seam (step 3) ────────────────────────────────────────────────
    # if $result.changed { dispatch project (store list) }
    # Persist first, project after: a projection that fails must never cost us a
    # fact, and an unchanged write must never reach a surface at all.

    $result
}
