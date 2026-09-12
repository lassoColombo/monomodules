# Every suite, one command:
#
#   use agent-notify2/tests; tests all
#
# or a single one, standalone and with no `-I` needed:
#
#   nu agent-notify2/tests/store.nu
#   nu agent-notify2/tests/claude.nu
#   nu agent-notify2/tests/codex.nu
#   nu agent-notify2/tests/dispatch.nu
#   nu agent-notify2/tests/zellij.nu
#   nu agent-notify2/tests/proc.nu
#   nu agent-notify2/tests/sketchybar.nu
#
# Not part of the module — nothing in ../mod.nu imports this, so `use agent-notify2`
# never parses a byte of it.
export use store.nu
export use claude.nu
export use codex.nu
export use dispatch.nu
export use zellij.nu
export use proc.nu
export use sketchybar.nu

# Run everything; returns false if any suite had a failure.
export def all []: nothing -> bool {
    # `where`, not `all`: this module exports a command called `all`, which
    # shadows the builtin of that name for this whole file (plan.md §10).
    let results = [(store) (claude) (codex) (dispatch) (zellij) (proc) (sketchybar)]
    ($results | where {|ok| not $ok } | is-empty)
}
