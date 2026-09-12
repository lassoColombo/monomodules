# The configuration file: what the user turns on, and what each tool is told.
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
#   zellij:                          # one namespace per tool, owned by it
#     binary: zellij                 #   what both halves share
#     surface:                       #   PUSH — how it SHOWS the store
#       glyphs: {working: 🧠, awaiting: 🔔}
#     commands: {}                   #   PULL — how its COMMANDS behave
#
# THE TWO HALVES ARE THE POINT (D47). A tool can do two unrelated things with the
# store, and they are not configured by the same switch:
#
#   PUSH   something already on screen, kept in sync as events arrive. Pane
#          titles, bar counters. `surfaces:` is what turns this on, and it is the
#          ONLY thing that list controls.
#   PULL   a command you invoke. The picker, the jump. It runs because you ran it.
#          Deleting a tool from `surfaces:` means "stop renaming my panes"; it
#          does not mean "take away my picker", so it must not.
#
# Splitting them in the FILE is what makes that unambiguous without a paragraph
# of explanation — which is why the halves are nested rather than flattened with
# prefixes.
#
# A key at the tool's own level (`binary` above) belongs to BOTH halves: the same
# program renames a pane and focuses one. Keys that are not shared live in the
# half that uses them, and a half a tool has nothing to say about is simply
# absent.
#
# A namespace for a tool that is not in `surfaces` is FINE — switching the push
# off should not mean deleting its colours, and its commands still work. A
# namespace naming a tool that does not exist is an error, because that is a typo.
#
# STRICT WHERE A HUMAN IS, LENIENT WHERE A HOOK IS. `problems` is exact, and
# `agent-notify config check` is what a human runs. `load` and `section` never
# throw: they are on the path of every tool call, and a typo in a YAML file must
# not be able to stop the store from recording facts. The cost of that choice is
# that a broken config shows up as "my bar stopped moving" rather than as an
# error — which is what `config check` is for, and why it names the file and the
# problem.

# The two halves of a tool's namespace. Everything else at that level is shared.
const HALVES = ["surface" "commands"]

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

# The tools the user asked to be PUSHED to, in the order they asked. Says nothing
# about commands — see the header.
export def enabled []: nothing -> list<string> {
    let v = (load).surfaces? | default []
    if (($v | describe) | str starts-with "list") { $v } else { [] }
}

# What one half of one tool was told: the keys it owns, on top of the ones it
# shares with its other half.
#
# Takes the config rather than reading it, so dispatch pays for one `open` and
# not one per surface. NEVER throws: a namespace that is not a map, or a half
# that is not a map, reads as "nothing was configured" — the tool's own
# `settings` is what turns that into a message, and only when a human asks.
export def section [cfg: record, tool: string, half: string]: nothing -> record {
    let ns = $cfg | get -o $tool
    if not (($ns | describe) | str starts-with "record") { return {} }
    let shared = $ns | reject --optional ...$HALVES
    let own = $ns | get -o $half
    if not (($own | describe) | str starts-with "record") { return $shared }
    $shared | merge $own
}

# Every problem with the file, in the order a human would fix them. An empty list
# means the file is good — or absent, which is also good: no file, no surfaces.
#
# Takes the shipped table rather than a list of names, because the last check
# needs each tool's own `settings`: only the tool knows what a key MEANS, and a
# misspelled colour is the failure this command exists to explain. That check runs
# for ENABLED tools only — settings for a tool you have switched off are not a
# problem, and resolving them can require a program you have not installed.
export def problems [surfaces: record]: nothing -> list<string> {
    let f = file
    if not ($f | path exists) { return [] }

    let read = try { {ok: true, data: (open $f)} } catch {|e| {ok: false, why: $e.msg} }
    if not $read.ok { return [$"cannot be read as YAML: ($read.why)"] }

    let cfg = $read.data
    if not (($cfg | describe) | str starts-with "record") {
        return [$"the file must be a map of settings, got ($cfg | describe)"]
    }

    let known = $surfaces | columns
    let names = if ($known | is-empty) { "none are installed yet" } else { $known | str join ", " }
    let asked = $cfg.surfaces? | default []
    mut problems = []

    if not (($asked | describe) | str starts-with "list") {
        $problems = $problems ++ [$"`surfaces` must be a list of names, got ($asked | describe)"]
    } else {
        for s in $asked {
            if (($s | describe) != "string") {
                $problems = $problems ++ [$"`surfaces` must hold names, found a ($s | describe)"]
            } else if ($s not-in $known) {
                $problems = $problems ++ [$"`surfaces` names '($s)', which is not a tool \(installed: ($names)\)"]
            }
        }
    }

    # The namespace rule, the store's rule: a top-level key the core does not own
    # belongs to a tool, must be spelled like one, and must be a record — as must
    # each of its halves.
    for k in ($cfg | columns | where {|k| $k != "surfaces" }) {
        let v = $cfg | get $k
        if ($k not-in $known) {
            $problems = $problems ++ [$"'($k)' is not a tool, so it does not belong at the top level"]
            continue
        }
        if not (($v | describe) | str starts-with "record") {
            $problems = $problems ++ [$"'($k)' must be a map of settings, got ($v | describe)"]
            continue
        }
        for half in $HALVES {
            let h = $v | get -o $half
            if ($h == null) { continue }
            if not (($h | describe) | str starts-with "record") {
                $problems = $problems ++ [$"'($k).($half)' must be a map of settings, got ($h | describe)"]
            }
        }
    }

    # And what the settings SAY, through the only thing that knows: the tool.
    let on = if (($asked | describe) | str starts-with "list") { $asked } else { [] }
    for k in ($on | where {|k| ($k | describe) == "string" } | where {|k| $k in $known } | uniq) {
        let entry = $surfaces | get $k
        let why = try {
            do $entry.settings (section $cfg $k "surface")
            null
        } catch {|e| $e.msg }
        if ($why == null) { continue }
        # A tool names itself in its own errors ("zellij: 'glyph' is not a
        # setting"), and saying it twice reads like a bug. Keep the tool's
        # sentence; say which HALF it came from.
        let owned = $why | str starts-with $"($k): "
        let msg = if $owned { $why | str substring (($k | str length) + 2).. } else { $why }
        $problems = $problems ++ [$"($k).surface: ($msg)"]
    }

    $problems
}
