# `agent-notify2 clients` — what can report into the store, and how to set it up.
#
# Cold by definition: this is the one place that imports every client at once, so
# it pays to parse all of them. No entry point comes near it.

use ../clients/claude.nu
use ../clients/codex.nu

# Each shipped client, with the states it can actually reach. That last column is
# not decoration: Codex's `notify` only ever says "the turn is over", so an agent
# integrated through it can never appear as working, and a surface built on the
# assumption that every agent reports everything would be wrong.
@search-terms agent notify clients agents list integrations
@example "what can report into the store" { agent-notify2 clients }
export def main []: nothing -> table {
    [$claude.INFO $codex.INFO] | each {|c| {
        name: $c.name
        agent: $c.title
        transport: $c.transport
        states: ($c.states | str join " ")
    }}
}

# How to wire one up. Printed rather than applied: every agent keeps its config in
# a different file in a different format, and merging into four foreign configs —
# with backups, existing entries and an uninstall path — is a great deal of blast
# radius for the convenience of not pasting a block yourself.
@search-terms agent notify wiring install setup hook config
@example "set up Codex" { agent-notify2 clients wiring codex }
export def wiring [name: string]: nothing -> string {
    match $name {
        "claude" => (claude wiring)
        "codex" => (codex wiring)
        _ => { error make --unspanned {msg: $"agent-notify: no client named '($name)' \(try: claude, codex\)"} }
    }
}
