# A surface that needs nothing installed: it writes a line to a file.
#
# It exists so the dispatch gate can be tested for real — with a store, a config
# file and two projections — on a machine with no zellij and no bar. Same move as
# `clients/codex.nu`: prove the contract on something we can actually run.
#
# It is a complete surface, and deliberately: four exports, the pure/impure split,
# its own strict settings. If step 4 cannot be written in this shape, the shape is
# wrong and this file is where that shows up first.

export const INFO = {name: "fake", title: "a line in a file, for tests"}

export def settings [given: record, me: any]: nothing -> record {
    let s = {glyphs: {working: "W", awaiting: "A", needs-attention: "!", idle: "."}} | merge $given
    let log = $s.log? | default ""
    if ($log | is-empty) {
        error make --unspanned {msg: "fake: `log` is required — nowhere to write"}
    }
    $s
}

# PURE. Note what it does NOT read: `message`, `updated_at`, `cwd`. That is the
# whole point of the gate — a turn that only changes the message projects to the
# same thing, so `apply` is never called.
export def project [records: list<record>, settings: record]: nothing -> list<string> {
    $records | each {|r| $"(($settings.glyphs | get -o $r.state) | default '?')($r.id)" }
}

export def apply [desired: list<string>, previous: any, settings: record]: nothing -> nothing {
    $"($desired | str join ' ')\n" | save --append $settings.log
}
