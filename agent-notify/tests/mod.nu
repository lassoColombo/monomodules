# Every suite, one command:
#
#   use agent-notify/tests; tests
#
# or a single one, standalone and with no `-I` needed:
#
#   nu agent-notify/tests/session-store.nu
#   nu agent-notify/tests/claude.nu
#   nu agent-notify/tests/codex.nu
#   nu agent-notify/tests/dispatch.nu
#   nu agent-notify/tests/zellij.nu
#   nu agent-notify/tests/proc.nu
#   nu agent-notify/tests/markdown.nu
#   nu agent-notify/tests/sketchybar.nu
#   nu agent-notify/tests/prune-daemon.nu
#   nu agent-notify/tests/jump.nu
#   nu agent-notify/tests/picker.nu
#
# Not part of the module — nothing in ../mod.nu imports this, so `use
# agent-notify` never parses a byte of it.
export use session-store.nu
export use claude.nu
export use codex.nu
export use dispatch.nu
export use zellij.nu
export use proc.nu
export use markdown.nu
export use sketchybar.nu
export use prune-daemon.nu
export use jump.nu
export use picker.nu

# Run everything; returns false if any suite had a failure.
#
# `main`, not `all`. A def named after a builtin shadows it for every module the
# file imports — so an `export def all` here silently broke `| all { … }` inside
# tests/prune-daemon.nu, in a file that never mentions the name. Exporting
# `main` means the runner is spelled `tests`, and no suite can be poisoned by it
# (§10).
export def main []: nothing -> bool {
    let results = [(session-store) (claude) (codex) (dispatch) (zellij) (proc) (markdown) (sketchybar) (prune-daemon) (jump) (picker)]
    ($results | where {|ok| not $ok } | is-empty)
}
