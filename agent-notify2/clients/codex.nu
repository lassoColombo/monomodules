# Codex CLI. The second client, and deliberately the most different one — it is
# here to prove the client contract rather than to confirm it.
#
# Almost nothing it does matches Claude Code:
#
#   transport   the payload arrives as a single ARGV element appended to whatever
#               program `notify` names, not on stdin
#   entry       therefore a SCRIPT, not a `-c` import: `nu -c '…' '<json>'`
#               silently discards the appended argument (verified), so `main` has
#               to be the thing receiving argv. Costs ~7.5ms more than the `-c`
#               form, which is irrelevant here — `notify` fires once per turn, not
#               once per tool call.
#   events      the event name lives INSIDE the payload, as `type`, because Codex
#               configures one notifier for everything rather than one per event
#   naming      kebab-case: `thread-id`, `last-assistant-message`
#   coverage    one event today, `agent-turn-complete`, so the only state reachable
#               through `notify` is `awaiting`. Codex has a SECOND mechanism —
#               `hooks.json` / `[hooks]`, with PreToolUse-style events — which is
#               what would add `working`. Not implemented here: one transport is
#               enough to prove the contract, and the second deserves its own
#               reading of the documentation rather than a guess.
#
# Every one of those differences is three lines of nushell in this file, and none
# of them leaks into the core. That is the whole argument for a module per agent.

use ../core/event.nu
use ../core/payload.nu

const SELF = path self

export const INFO = {
    name: "codex"
    title: "Codex CLI"
    transport: "argv-json"
    states: ["awaiting"]
}

# Named `ignored`, not `ignore`: a def shadows the builtin of that name for the
# whole file, and the very next line pipes to the builtin `ignore` (plan.md §10).
def ignored [why: string]: nothing -> record { {op: "ignore", why: $why} }

def said [text: any]: nothing -> any {
    let t = $text | default "" | str trim
    if ($t | is-empty) { null } else { $t }
}

export def map [event: string, payload: record]: nothing -> record {
    let id = $payload | get -o "thread-id" | default ""
    if ($id | is-empty) { return (ignored "payload carries no thread-id") }

    match $event {
        # The turn is over and it is your move. Codex has no matching "started"
        # event, so an agent integrated this way alternates between awaiting and
        # whatever the last thing to touch its record said.
        "agent-turn-complete" => {
            op: "patch"
            id: $id
            changes: {
                client: "codex"
                state: "awaiting"
                cwd: ($payload.cwd? | default "")
                message: (said ($payload | get -o "last-assistant-message"))
                codex: {turn_id: ($payload | get -o "turn-id" | default "")}
            }
            defaults: {}
        }
        _ => (ignored $"unhandled event '($event)'")
    }
}

# A SCRIPT entry: Codex appends the JSON to our argv, so `main` is what receives
# it. The event name comes out of the payload rather than the command line, which
# is why `...args` is taken loosely — where Codex puts the blob is its business.
export def main [...args: string] {
    try {
        let body = payload from-args $args
        let event = $body.type? | default ""
        event apply (map $event $body) | ignore
    }
}

export def wiring []: nothing -> string {
    ([ "Add to ~/.codex/config.toml:"
       ""
       $"notify = [\"nu\", \"-n\", \"--no-std-lib\", \"($SELF)\"]"
       ""
       "Codex appends the event JSON as a final argument, so this is a script"
       "entry rather than the `-c` import the Claude client uses." ] | str join "\n")
}
