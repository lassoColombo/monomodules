# What a record is, and the only things the core insists on.
#
# The session-schema is OPEN (plan.md §4.1): a closed one would make the core
# depend on every integration's fields, so adding an integration would mean
# editing core — which is exactly what opt-in integrations must not require. The
# core therefore guarantees a small set of fields and owns their policy, and
# everything else lives in a namespace named after its owner, integration or
# agent alike.
#
# One thing is deliberately closed: the STATE VOCABULARY. Displays render states
# — three counters, three glyphs, an urgency order — and a bar cannot draw a
# state it has never heard of. A shared vocabulary is what an adapter adapts
# *to*, so closing it is the mechanism that makes agent-agnosticism work rather
# than a limit on it. Every agent maps its own concepts onto these four.

export const VERSION = 1

export const STATES = ["working" "awaiting" "needs-attention" "idle"]

# Fields the core knows about. Everything else must be a namespace (a record).
const CORE_REQUIRED = ["id" "agent" "state"]
const CORE_OPTIONAL = ["name" "cwd" "message"]

# Set by the session-store, never by a caller, and EXCLUDED from the `changed`
# comparison — otherwise every write would look like a change and `changed`
# would be useless as the gate the whole event path hangs off.
export const STAMPED_FIELDS = ["schema_version" "updated_at" "state_since"]

# Timestamps are stored as UTC ISO-8601 STRINGS, not as nushell datetimes, for
# two reasons: `to json` renders a datetime with the local offset (so a record
# written in Rome and read in UTC would differ textually), and the session-store
# is JSON on purpose — a foreign agent must be able to read it without nushell.
# Forcing UTC also means lexicographic order is chronological order.
export def now-stamp []: nothing -> string {
    date now | date to-timezone UTC | format date "%Y-%m-%dT%H:%M:%S%.6fZ"
}

# The comparable part of a record: everything the core did not stamp itself.
export def comparable-fields [rec: record]: nothing -> record {
    $rec | reject --optional ...$STAMPED_FIELDS
}

# What describes the SESSION rather than the run that happened to be in it.
#
# The line is one the session-schema already draws and needs no second list: the
# CORE fields say what this session IS — who owns it, what it is called, where
# it works, what it last said — and every namespace belongs to one RUN. `proc`
# is one process. `zellij` is one pane. `claude` is one transcript. None of them
# survives a restart, and none of them should survive being filed away and taken
# back out (core/session-store.nu `reopen-session`).
export def session-fields [rec: record]: nothing -> record {
    let keep = $CORE_REQUIRED ++ $CORE_OPTIONAL
    $rec | select ...($rec | columns | where {|k| $k in $keep })
}

# Apply the core's stamps. `state_since` moves only when the state genuinely
# changes, so "how long has it been waiting?" survives every unrelated write.
export def stamp [before: any, merged: record]: nothing -> record {
    let now = now-stamp
    let moved = ($before == null) or (($before.state? | default "") != ($merged.state? | default ""))
    $merged | merge {
        schema_version: $VERSION
        updated_at: $now
        state_since: (if $moved { $now } else { $before.state_since? | default $now })
    }
}

# Strict where it matters, open everywhere else. Validation runs on the RESULT
# of a write rather than on its input, which is what lets `patch` both create
# and update through one code path: either way, what ends up on disk must be
# valid.
export def validate [rec: record]: nothing -> record {
    for f in $CORE_REQUIRED {
        let v = $rec | get -o $f
        if ($v == null) or (($v | describe) != "string") or (($v | str trim) | is-empty) {
            error make --unspanned {msg: $"agent-notify: record is missing required field '($f)' \(a non-empty string\)"}
        }
    }
    if ($rec.state not-in $STATES) {
        error make --unspanned {msg: $"agent-notify: unknown state '($rec.state)' \(want one of: ($STATES | str join ', ')\)"}
    }
    for f in $CORE_OPTIONAL {
        let v = $rec | get -o $f
        if ($v != null) and (($v | describe) != "string") {
            error make --unspanned {msg: $"agent-notify: field '($f)' must be a string, got ($v | describe)"}
        }
    }
    # The namespace rule, enforced without knowing who the owners are: any
    # top-level key the core does not own has to be a record. That is what keeps
    # `zellij: {...}` from degenerating into a scatter of `zellij_tab_id`
    # fields.
    let known = $CORE_REQUIRED ++ $CORE_OPTIONAL ++ $STAMPED_FIELDS
    for k in ($rec | columns | where {|k| $k not-in $known }) {
        let v = $rec | get $k
        if not (($v | describe) | str starts-with "record") {
            error make --unspanned {msg: $"agent-notify: '($k)' is not a core field, so it must be a namespace \(a record\), got ($v | describe)"}
        }
    }
    $rec
}
