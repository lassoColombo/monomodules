# Every suite, one command:
#
#   use agent-notify2/tests; tests
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
#   nu agent-notify2/tests/clock.nu
#   nu agent-notify2/tests/jump.nu
#   nu agent-notify2/tests/browse.nu
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
export use clock.nu
export use jump.nu
export use browse.nu

# Run everything; returns false if any suite had a failure.
#
# `main`, not `all`. A def named after a builtin shadows it for every module the
# file imports — so an `export def all` here silently broke `| all { … }` inside
# tests/clock.nu, in a file that never mentions the name. Exporting `main` means
# the runner is spelled `tests`, and no suite can be poisoned by it (§10).
export def main []: nothing -> bool {
    let results = [(store) (claude) (codex) (dispatch) (zellij) (proc) (sketchybar) (clock) (jump) (browse)]
    ($results | where {|ok| not $ok } | is-empty)
}
