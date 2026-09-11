# Step 2b — the Codex client, which exists to prove the contract holds for an
# agent that shares almost nothing with Claude Code: the payload arrives on argv
# rather than stdin, the event name lives inside it, the fields are kebab-case,
# and the entry has to be a script because `nu -c '…' '<json>'` discards the
# appended argument.
#
# The last section runs the real thing the way Codex's `notify` will run it.

use ../../agent-notify2
use ../clients/codex.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-codex")
const CLIENT = path self ../clients/codex.nu

def turn [extra: record = {}]: nothing -> record {
    { type: "agent-turn-complete", "thread-id": "th-77", "turn-id": "t-3"
      cwd: "/Users/x/work", "input-messages": ["do the thing"]
      "last-assistant-message": "Did the thing." } | merge $extra
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP

    let m = [
        (check "a completed turn hands control back"
               (codex map "agent-turn-complete" (turn) | get changes.state) "awaiting")
        (check "identity comes from the kebab-cased thread-id"
               (codex map "agent-turn-complete" (turn) | get id) "th-77")
        (check "…and the message from last-assistant-message"
               (codex map "agent-turn-complete" (turn) | get changes.message) "Did the thing.")
        (check "the client names itself"
               (codex map "agent-turn-complete" (turn) | get changes.client) "codex")
        (check "codex-only facts stay in the codex namespace"
               (codex map "agent-turn-complete" (turn) | get changes.codex.turn_id) "t-3")
        (check "an empty message clears rather than lingers"
               (codex map "agent-turn-complete" (turn {"last-assistant-message": "  "})
                | get changes.message) null)
        (check "a payload with no thread-id is ignored"
               (codex map "agent-turn-complete" {type: "agent-turn-complete"} | get op) "ignore")
        (check "an event Codex has not invented yet is ignored"
               (codex map "something-new" (turn) | get op) "ignore")
    ]

    # ── the entry, exactly as `notify` will invoke it ────────────────────────
    # A script, with the JSON appended to argv — the shape Codex imposes.
    let r = ^$nu.current-exe -n --no-std-lib $CLIENT ((turn) | to json --raw) | complete
    let rec = agent-notify2 store get "th-77"
    let e = [
        (check "the notifier exits 0" $r.exit_code 0)
        (check "…and prints nothing" ($r.stdout + $r.stderr) "")
        (check "the store saw the turn end" $rec.state "awaiting")
        (check "…with the message" $rec.message "Did the thing.")
        (check "…and under the right client" $rec.client "codex")
        (check "a junk argument cannot break the notifier"
               ((^$nu.current-exe -n --no-std-lib $CLIENT "not json" | complete).exit_code) 0)
        (check "no argument at all cannot break it"
               ((^$nu.current-exe -n --no-std-lib $CLIENT | complete).exit_code) 0)
    ]

    # Two clients, one store, no collision.
    let both = agent-notify2 store list | get client | sort | uniq
    let c = [ (check "codex and claude coexist in one store" $both ["codex"]) ]

    summarise ($m ++ $e ++ $c) --title "codex client"
}
