# `agent-notify2 surfaces` — what can show the store, and whether it is on.
#
# Cold by definition: this is the one place that looks at every surface at once.

use ../core/config.nu
use ../core/dispatch.nu
use ../core/janitor.nu
use ../surfaces/sketchybar.nu

@search-terms agent notify surfaces integrations zellij sketchybar list enabled
@example "what can show the store?" { agent-notify2 surfaces }
export def main []: nothing -> table {
    let on = config enabled
    dispatch shipped
    | transpose name entry
    | each {|s| {name: $s.name, surface: $s.entry.info.title, enabled: ($s.name in $on)} }
}

# Repaint everything, whatever the store did or did not do. The recovery command
# after editing the config, and what a periodic trigger will call: it skips the
# gate in `core/dispatch.nu` rather than asking whether anything changed.
@search-terms agent notify surfaces refresh repaint redraw force
@example "repaint after editing the config" { agent-notify2 surfaces refresh }
export def refresh []: nothing -> table {
    # PRUNE FIRST. A repaint should not spend a zellij call on an agent that is
    # not there, and this is the one path that runs often enough to be the system's
    # janitor without ever touching a hook — step 5's bar timer calls it.
    janitor prune | ignore

    dispatch project --force
}

# Create a surface's items on the bar. Unlike `clients wiring`, this one ACTS:
# SketchyBar items are runtime state, not a file in someone's config directory,
# and creating them is the only way a fixed pool can exist at all. What goes in
# your `sketchybarrc` is still only printed — see `surfaces wiring`.
@search-terms agent notify surfaces install scaffold sketchybar items pool
@example "create the bar items" { agent-notify2 surfaces install sketchybar }
export def install [name: string]: nothing -> nothing {
    let cfg = config load
    match $name {
        "sketchybar" => {
            sketchybar install (sketchybar settings ($cfg | get -o sketchybar | default {}) null)
            print $"(ansi green)installed(ansi reset) the SketchyBar counters"
        }
        "zellij" => { print "zellij needs no installation — it renames panes directly." }
        _ => { error make --unspanned {msg: $"agent-notify: no surface named '($name)' \(try: zellij, sketchybar\)"} }
    }
}

# What to put in the surface's own config so it survives a restart. Printed, never
# applied (D20).
@search-terms agent notify surfaces wiring setup sketchybarrc config
@example "how do I keep the bar items?" { agent-notify2 surfaces wiring sketchybar }
export def wiring [name: string]: nothing -> string {
    match $name {
        "sketchybar" => (sketchybar wiring)
        "zellij" => "zellij needs no wiring — agent-notify renames panes itself."
        _ => { error make --unspanned {msg: $"agent-notify: no surface named '($name)' \(try: zellij, sketchybar\)"} }
    }
}
