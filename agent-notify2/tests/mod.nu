# Every suite, one command:
#
#   use agent-notify2/tests; tests all
#
# or a single one, standalone and with no `-I` needed:
#
#   nu agent-notify2/tests/store.nu
#   nu agent-notify2/tests/claude.nu
#   nu agent-notify2/tests/codex.nu
#
# Not part of the module — nothing in ../mod.nu imports this, so `use agent-notify2`
# never parses a byte of it.
export use store.nu
export use claude.nu
export use codex.nu

# Run everything; returns false if any suite had a failure.
export def all []: nothing -> bool {
    # `where`, not `all`: this module exports a command called `all`, which
    # shadows the builtin of that name for this whole file (plan.md §10).
    let results = [(store) (claude) (codex)]
    ($results | where {|ok| not $ok } | is-empty)
}
