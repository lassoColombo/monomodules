# `agent-notify2 surfaces` — what can show the store, and whether it is on.
#
# Cold by definition: this is the one place that looks at every surface at once.

use ../core/config.nu
use ../core/dispatch.nu

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
    dispatch project --force
}
