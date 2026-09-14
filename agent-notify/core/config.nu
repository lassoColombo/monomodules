# The configuration file: what the user turns on, and what each tool is told.
#
# A FILE, not `config.nu` (D3). Every other module in this repo reads its
# settings from `$env`, set in the user's `config.nu`, and that is right for
# them: they are typed at a prompt by a human in a configured shell. This module
# is invoked by Claude Code, by sketchybar, by zellij — processes with no shell
# config, where `nu -n` cannot see a thing `config.nu` set. `source` would work
# but is parse-time: a missing file becomes a parse failure and the path cannot
# be chosen at runtime. `open` has neither problem and costs 0.06ms.
#
# THE SHAPE IS THE SESSION-STORE'S SHAPE: a small core the module owns, plus one
# namespace per owner, and anything the core does not recognise is an error. One
# idea, two files.
#
#   displays: [zellij, sketchybar]   # the opt-in list; its order is dispatch order
#
#   zellij:                          # one namespace per tool, owned by it
#     binary: zellij                 #   what both halves share
#     display:                       #   PUSH — how it SHOWS the session-store
#       glyphs: {working: 🧠, awaiting: 🔔}
#     commands: {}                   #   PULL — how its COMMANDS behave
#
# THE TWO HALVES ARE THE POINT (D47). A tool can do two unrelated things
# with the session-store, and they are not configured by the same switch:
#
#   PUSH   something already on screen, kept in sync as events arrive. Pane
#          titles, bar counters. `displays:` is what turns this on, and it is the
#          ONLY thing that list controls.
#   PULL   a command you invoke. The picker, the jump. It runs because you ran it.
#          Deleting a tool from `displays:` means "stop renaming my panes"; it
#          does not mean "take away my picker", so it must not.
#
# Splitting them in the FILE is what makes that unambiguous without a paragraph
# of explanation — which is why the halves are nested rather than flattened with
# prefixes.
#
# A key at the tool's own level (`binary` above) belongs to BOTH halves: the
# same program renames a pane and focuses one. Keys that are not shared live in
# the half that uses them, and a half a tool has nothing to say about is simply
# absent.
#
# A namespace for a tool that is not in `displays` is FINE — switching the push
# off should not mean deleting its colours, and its commands still work. A
# namespace naming a tool that does not exist is an error, because that is a
# typo.
#
# STRICT WHERE A HUMAN IS, LENIENT WHERE A HOOK IS. `problems` is exact, and
# `agent-notify config check` is what a human runs. `load` and `settings-for` never
# throw: they are on the path of every tool call, and a typo in a YAML file must
# not be able to stop the session-store from recording facts. The cost of that
# choice is that a broken config shows up as "my bar stopped moving" rather than
# as an error — which is what `config check` is for, and why it names the file
# and the problem.

# The two halves of a tool's namespace. Everything else at that level is shared.
const TOOL_SECTIONS = ["display" "commands"]

# Where the file is. `$env.AGENT_NOTIFY_CONFIG` wins (tests and one-offs), then
# XDG, then the default. Named `file` rather than `path` because `path` is a
# builtin and a def would shadow it for every module that imports this one
# (§10).
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

# The tools the user asked to be PUSHED to, in the order they asked. Says
# nothing about commands — see the header.
export def enabled []: nothing -> list<string> {
    let v = (load).displays? | default []
    if (($v | describe) | str starts-with "list") { $v } else { [] }
}

# What one half of one tool was told: the keys it owns, on top of the ones it
# shares with its other half.
#
# Takes the config rather than reading it, so dispatch pays for one `open` and
# not one per display. NEVER throws: a namespace that is not a map, or a half
# that is not a map, reads as "nothing was configured" — the tool's own
# `settings` is what turns that into a message, and only when a human asks.
export def settings-for [cfg: record, tool: string, half: string]: nothing -> record {
    let ns = $cfg | get -o $tool
    if not (($ns | describe) | str starts-with "record") { return {} }
    let shared = $ns | reject --optional ...$TOOL_SECTIONS
    let own = $ns | get -o $half
    if not (($own | describe) | str starts-with "record") { return $shared }
    $shared | merge $own
}

# Every problem with the file, in the order a human would fix them. An empty
# list means the file is good — or absent, which is also good: no file, no
# displays.
#
# Takes the integration-registry tables rather than lists of names, because the
# last checks need each tool's own `settings`: only the tool knows what a key
# MEANS, and a misspelled colour is the failure this command exists to explain.
#
# TWO TABLES, because an integration has CAPABILITIES and not a kind (D70). A
# container-only integration — aerospace shows nothing, it just holds windows —
# is in no display registry, so with one table its namespace reads as a typo and
# `agent-notify config check` refuses a perfectly good file. That was found by
# writing an `aerospace:` block and watching it be rejected.
#
# The two halves are checked on different terms. The DISPLAY half, for ENABLED
# tools only — settings for a display you switched off are not a problem, and
# resolving them can require a program you have not installed. The COMMANDS
# half, WHETHER OR NOT the tool is in `displays:`, because nothing turns
# commands on: you run a jump and it runs, so a typo there is always live.
#
# `containers` is optional so older callers are unaffected; an empty table means
# the commands half is simply not checked.
export def problems [displays: record, containers: record = {}]: nothing -> list<string> {
    let f = file
    if not ($f | path exists) { return [] }

    let read = try { {ok: true, data: (open $f)} } catch {|e| {ok: false, why: $e.msg} }
    if not $read.ok { return [$"cannot be read as YAML: ($read.why)"] }

    let cfg = $read.data
    if not (($cfg | describe) | str starts-with "record") {
        return [$"the file must be a map of settings, got ($cfg | describe)"]
    }

    # A tool is anything with a capability, not just anything that displays.
    let known_tools = ($displays | columns) ++ ($containers | columns) | uniq
    let names = if ($known_tools | is-empty) { "none are installed yet" } else { $known_tools | str join ", " }
    let asked = $cfg.displays? | default []
    mut problems = []

    if not (($asked | describe) | str starts-with "list") {
        $problems = $problems ++ [$"`displays` must be a list of names, got ($asked | describe)"]
    } else {
        for s in $asked {
            if (($s | describe) != "string") {
                $problems = $problems ++ [$"`displays` must hold names, found a ($s | describe)"]
            } else if ($s not-in $known_tools) {
                $problems = $problems ++ [$"`displays` names '($s)', which is not a tool \(installed: ($names)\)"]
            }
        }
    }

    # The namespace rule, the session-store's rule: a top-level key the core
    # does not own belongs to a tool, must be spelled like one, and must be a
    # record — as must each of its halves.
    for k in ($cfg | columns | where {|k| $k != "displays" }) {
        let v = $cfg | get $k
        if ($k not-in $known_tools) {
            $problems = $problems ++ [$"'($k)' is not a tool, so it does not belong at the top level"]
            continue
        }
        if not (($v | describe) | str starts-with "record") {
            $problems = $problems ++ [$"'($k)' must be a map of settings, got ($v | describe)"]
            continue
        }
        for half in $TOOL_SECTIONS {
            let h = $v | get -o $half
            if ($h == null) { continue }
            if not (($h | describe) | str starts-with "record") {
                $problems = $problems ++ [$"'($k).($half)' must be a map of settings, got ($h | describe)"]
            }
        }
    }

    # And what the settings SAY, through the only thing that knows: the tool.
    let on = if (($asked | describe) | str starts-with "list") { $asked } else { [] }
    for k in ($on | where {|k| ($k | describe) == "string" } | where {|k| $k in $known_tools } | uniq) {
        let entry = $displays | get $k
        let why = try {
            do $entry.settings (settings-for $cfg $k "display")
            null
        } catch {|e| $e.msg }
        if ($why == null) { continue }
        # A tool names itself in its own errors ("zellij: 'glyph' is not a
        # setting"), and saying it twice reads like a bug. Keep the tool's
        # sentence; say which HALF it came from.
        let owned = $why | str starts-with $"($k): "
        let msg = if $owned { $why | str substring (($k | str length) + 2).. } else { $why }
        $problems = $problems ++ [$"($k).display: ($msg)"]
    }

    # And the COMMANDS half, for every tool that has one — enabled or not.
    for k in ($containers | columns | where {|k| $k in ($cfg | columns) }) {
        let entry = $containers | get $k
        if ($entry.commands-settings? == null) { continue }
        let why = try {
            do $entry.commands-settings (settings-for $cfg $k "commands")
            null
        } catch {|e| $e.msg }
        if ($why == null) { continue }
        let owned = $why | str starts-with $"($k): "
        let msg = if $owned { $why | str substring (($k | str length) + 2).. } else { $why }
        $problems = $problems ++ [$"($k).commands: ($msg)"]
    }

    $problems
}
