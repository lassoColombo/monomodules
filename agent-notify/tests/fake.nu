# A display that needs nothing installed: it writes a line to a file.
#
# It exists so the gate and the diff can be tested for real — two session-store
# snapshots, a config file, a map in and a map out — on a machine with no zellij
# and no bar. Same move as `agents/codex.nu`: prove the contract on something
# we can actually run.
#
# It is a complete display, deliberately: the four parts, the pure/impure split,
# its own strict settings. If a real display cannot be written in this shape,
# the shape is wrong and this file is where that shows up first.

export const INFO = {name: "fake", title: "a line in a file, for tests"}

export def settings [given: record]: nothing -> record {
    let s = {glyphs: {working: "W", awaiting: "A", needs-attention: "!", idle: "."}} | merge $given
    let log = $s.log? | default ""
    if ($log | is-empty) {
        error make --unspanned {msg: "fake: `log` is required — nowhere to write"}
    }
    $s
}

# PURE, and keyed by agent. Note what it does NOT read: `message`, `updated_at`,
# `cwd`. That is the whole point of the gate — a turn that only changes the
# message projects to the same map, so nothing is written.
export def render-items [records: list<record>, settings: record]: nothing -> record {
    mut out = {}
    for r in $records {
        $out = ($out | upsert $r.id (($settings.glyphs | get -o $r.state) | default "?"))
    }
    $out
}

export def push-items [changed: record, removed: record, settings: record]: nothing -> nothing {
    let wrote = $changed | columns | each {|k| $"($changed | get $k)($k)" }
    let undid = $removed | columns | each {|k| $"-($k)" }
    $"(($wrote ++ $undid) | str join ' ')\n" | save --append $settings.log
}

# ── and a SESSION-CONTAINER ───────────────────────────────────────────────────
#
# The other capability an integration can have (plan.md §4.8), in the same
# spirit: every question answered out of the record itself, so the whole picker
# — rows, filtering, scrolling, frames, keys — can be asserted on a machine with
# no zellij and no tmux.
#
#   {fake: {where: "box/one"}}
#
# `focus-session` does nothing. Where a jump would take you is `jump argv`'s
# business and it has its own suite; what this file proves is that the CONTRACT
# is answerable without the tool, which is the only claim
# `integrations/session-containers.nu` makes.

export const CONTAINER_INFO = {name: "fake", title: "a pane in a record, for tests"}

export def owns-session [rec: record]: nothing -> bool {
    (($rec.fake?.where? | default "") | is-not-empty)
}

export def location-label [rec: record]: nothing -> string { $rec.fake?.where? | default "" }

export def focus-session-argv [rec: record]: nothing -> list<list<string>> {
    [["echo" "fake" ($rec.fake?.where? | default "")]]
}

export def session-container []: nothing -> record {
    { fake: {info: $CONTAINER_INFO
             owns-session: {|rec| owns-session $rec }
             location-label: {|rec| location-label $rec }
             focus-session-argv: {|rec| focus-session-argv $rec }
             focus-session: {|rec| null }} }
}

# ── AND AN OUTER ONE, so the CHAIN can be exercised ───────────────────────────
#
# A session is at a PATH through containers (D77), so one fake proves the
# contract and two prove the walk. This one is deliberately the awkward shape
# the real outer container has: it cannot tell from the record alone whether it
# can actually reach the session, because only the world knows — so it CLAIMS
# OPTIMISTICALLY and finds out in `focus-session-argv`, which is the member
# allowed to look. `owns-session` stays free, which is what the picker needs: it
# asks every record, every two seconds.
#
#   {fake: {where: "box/one", outer: "desk-3"}}   claimed, and reachable
#   {fake: {where: "box/one"}}                    claimed, and nowhere to go
#
# `location-label` is "" on purpose: a container with nothing worth a column
# should drop out of the path rather than pad it.
export const OUTER_INFO = {name: "fake-outer", title: "whatever the box sits on"}

export def outer-owns-session [rec: record]: nothing -> bool {
    (($rec.fake?.where? | default "") | is-not-empty)
}

export def outer-focus-session-argv [rec: record]: nothing -> list<list<string>> {
    let handle = $rec.fake?.outer? | default ""
    if ($handle | is-empty) { [] } else { [["echo" "outer" $handle]] }
}

# OUTERMOST FIRST — the order of this record is the nesting order (D78).
export def session-container-chain []: nothing -> record {
    { fake-outer: {info: $OUTER_INFO
                   owns-session: {|rec| outer-owns-session $rec }
                   location-label: {|rec| "" }
                   focus-session-argv: {|rec| outer-focus-session-argv $rec }
                   focus-session: {|rec| null }} }
    | merge (session-container)
}
