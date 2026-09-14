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
# spirit: three questions answered out of the record itself, so the whole picker
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

# The `commands` half of this tool's namespace, validated. Present so the
# contract's optional fifth member is exercised too: `agent-notify config check`
# asks a container what its own settings mean, exactly as it asks a display, and
# it asks WHETHER OR NOT the tool is in `displays:` — nothing turns commands on.
export def commands-settings [given: record] {
    for k in ($given | columns | where {|k| $k != "where" }) {
        error make --unspanned {msg: $"fake: '($k)' is not a command setting"}
    }
    $given
}

export def session-container []: nothing -> record {
    { fake: {info: $CONTAINER_INFO
             owns-session: {|rec| owns-session $rec }
             location-label: {|rec| location-label $rec }
             commands-settings: {|given| commands-settings $given }
             focus-session-argv: {|rec| [["echo" "fake"]] }
             focus-session: {|rec| null }} }
}
