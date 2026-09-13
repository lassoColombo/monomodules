# `agent-notify displays` — what can show the session-store, and whether it is
# on.
#
# Cold by definition: this is the one place that looks at every display at once.

use ../core/config.nu
use ../core/dispatch.nu
use ../core/store-garbage-collector.nu
use ../core/session-store.nu
use ../integrations/sketchybar

@search-terms agent notify displays integrations zellij sketchybar list enabled
@example "what can show the session-store?" { agent-notify displays }
export def main []: nothing -> table {
    let on = config enabled
    dispatch integration-registry
    | transpose name entry
    | each {|s| {name: $s.name, display: $s.entry.info.title, enabled: ($s.name in $on)} }
}

# Repaint everything, whatever the session-store did or did not do. The recovery
# command after editing the config, and what a periodic trigger will call: it
# skips the gate in `core/dispatch.nu` rather than asking whether anything
# changed.
@search-terms agent notify displays refresh repaint redraw force
@example "repaint after editing the config" { agent-notify displays refresh }
export def refresh []: nothing -> table {
    # PRUNE FIRST, and hand the casualties to the repaint. A pruned agent is the
    # one thing no hook will ever report, so this is the only chance to undo
    # what it left on screen — its pane title outlives it otherwise.
    let gone = store-garbage-collector sweep-dead-sessions
    let now = session-store list
    dispatch repaint ($gone ++ $now) $now --force
}

# Create a display's items on the bar. Unlike `agents help-setup`, this one
# ACTS: SketchyBar items are runtime state, not a file in someone's config
# directory, and creating them is the only way a fixed pool can exist at all.
# What goes in your `sketchybarrc` is still only printed — see `displays
# help-setup`.
@search-terms agent notify displays install scaffold sketchybar items pool
@example "create the bar items" { agent-notify displays install sketchybar }
export def install [name: string]: nothing -> nothing {
    let cfg = config load
    match $name {
        "sketchybar" => {
            sketchybar install (sketchybar settings ($cfg | get -o sketchybar | default {}))
            # AND PAINT. The pool arrives blank, and this runs from
            # `sketchybarrc` — so without a repaint the bar shows three zeros
            # and three empty drawers until the next agent happens to say
            # something.
            refresh | ignore
            print $"(ansi green)installed(ansi reset) the SketchyBar counters"
        }
        "zellij" => { print "zellij needs no installation — it renames panes directly." }
        _ => { error make --unspanned {msg: $"agent-notify: no display named '($name)' \(try: zellij, sketchybar\)"} }
    }
}

# What to put in the display's own config so it survives a restart. Printed,
# never applied (D20).
@search-terms agent notify displays help-setup setup sketchybarrc config
@example "how do I keep the bar items?" { agent-notify displays help-setup sketchybar }
export def help-setup [name: string]: nothing -> string {
    match $name {
        "sketchybar" => (sketchybar help-setup)
        "zellij" => "zellij needs no help-setup — agent-notify renames panes itself."
        _ => { error make --unspanned {msg: $"agent-notify: no display named '($name)' \(try: zellij, sketchybar\)"} }
    }
}
