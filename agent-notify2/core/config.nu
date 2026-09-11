# The configuration file: what the user turns on, and what each surface is told.
#
# A FILE, not `config.nu` (D3). Every other module in this repo reads its settings
# from `$env`, set in the user's `config.nu`, and that is right for them: they are
# typed at a prompt by a human in a configured shell. This module is invoked by
# Claude Code, by sketchybar, by zellij — processes with no shell config, where
# `nu -n` cannot see a thing `config.nu` set. `source` would work but is
# parse-time: a missing file becomes a parse failure and the path cannot be chosen
# at runtime. `open` has neither problem and costs 0.06ms.
#
# THE SHAPE IS THE STORE'S SHAPE: a small core the module owns, plus one namespace
# per owner, and anything the core does not recognise is an error. One idea, two
# files.
#
#   surfaces: [zellij, sketchybar]   # the opt-in list; its order is dispatch order
#
#   zellij:                          # one namespace per surface, owned by it
#     glyphs: {working: 🧠, awaiting: 🔔}
#
# A namespace for a surface that is not in `surfaces` is FINE — switching a
# surface off should not mean deleting its colours. A namespace naming a surface
# that does not exist is an error, because that is a typo.
#
# STRICT WHERE A HUMAN IS, LENIENT WHERE A HOOK IS. `problems` is exact, and
# `agent-notify2 config check` is what a human runs. `load` never throws: it is on
# the path of every tool call, and a typo in a YAML file must not be able to stop
# the store from recording facts. The cost of that choice is that a broken config
# shows up as "my bar stopped moving" rather than as an error — which is what
# `config check` is for, and why it names the file and the problem.

# Where the file is. `$env.AGENT_NOTIFY_CONFIG` wins (tests and one-offs), then
# XDG, then the default. Named `file` rather than `path` because `path` is a
# builtin and a def would shadow it for every module that imports this one (§10).
export def file []: nothing -> string {
    let override = $env.AGENT_NOTIFY_CONFIG? | default ""
    if ($override | is-not-empty) { return $override }
    let base = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join ".config")
    $base | path join "agent-notify" "config.yaml"
}

# The config as data, or an empty record. NEVER throws — see the header.
export def load []: nothing -> record {
    let f = file
    if not ($f | path exists) { return {} }
    let parsed = try { open $f } catch { {} }
    if (($parsed | describe) | str starts-with "record") { $parsed } else { {} }
}

# The surfaces the user asked for, in the order they asked for them.
export def enabled []: nothing -> list<string> {
    let v = (load).surfaces? | default []
    if (($v | describe) | str starts-with "list") { $v } else { [] }
}

# Every problem with the file, in the order a human would fix them. An empty list
# means the file is good — or absent, which is also good: no file, no surfaces.
export def problems [known: list<string>]: nothing -> list<string> {
    let f = file
    if not ($f | path exists) { return [] }

    let read = try { {ok: true, data: (open $f)} } catch {|e| {ok: false, why: $e.msg} }
    if not $read.ok { return [$"cannot be read as YAML: ($read.why)"] }

    let cfg = $read.data
    if not (($cfg | describe) | str starts-with "record") {
        return [$"the file must be a map of settings, got ($cfg | describe)"]
    }

    let surfaces = $cfg.surfaces? | default []
    let names = if ($known | is-empty) { "none are installed yet" } else { $known | str join ", " }
    mut problems = []

    if not (($surfaces | describe) | str starts-with "list") {
        $problems = $problems ++ [$"`surfaces` must be a list of names, got ($surfaces | describe)"]
    } else {
        for s in $surfaces {
            if (($s | describe) != "string") {
                $problems = $problems ++ [$"`surfaces` must hold names, found a ($s | describe)"]
            } else if ($s not-in $known) {
                $problems = $problems ++ [$"`surfaces` names '($s)', which is not a surface \(installed: ($names)\)"]
            }
        }
    }

    # The namespace rule, the store's rule: a top-level key the core does not own
    # belongs to a surface, must be spelled like one, and must be a record.
    for k in ($cfg | columns | where {|k| $k != "surfaces" }) {
        let v = $cfg | get $k
        if ($k not-in $known) {
            $problems = $problems ++ [$"'($k)' is not a surface, so it does not belong at the top level"]
        } else if not (($v | describe) | str starts-with "record") {
            $problems = $problems ++ [$"'($k)' must be a map of settings, got ($v | describe)"]
        }
    }

    $problems
}
