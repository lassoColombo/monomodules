# Step 3, rewritten for the contract of step 7b — the config file, and the diff.
#
# The section to read is B. A display says what should be shown, as a map; this
# is where "what changed" is worked out, once, for every display that will ever
# exist. Everything here runs against a real session-store and a real config
# file, with `tests/fake.nu` standing in for zellij.

use ../../agent-notify
use ../core/config.nu
use ../core/dispatch.nu
use ../core/operation.nu
use ../core/session-store.nu
use fake.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-dispatch")
const LOG = ($nu.temp-dir | path join "agent-notify-tests-dispatch" "display.log")
const CFG = ($nu.temp-dir | path join "agent-notify-tests-dispatch" "config.yaml")

# The integration-registry table's shape, by hand — exactly what
# `core/dispatch.nu` holds. `boom` proves one display cannot take another down
# with it.
def displays []: nothing -> record {
    { boom: {info: {name: "boom", title: "always fails"}
             settings: {|given| $given }
             render-items: {|recs, s| {all: ($recs | length)} }
             push-items: {|changed, removed, s| error make --unspanned {msg: "boom: no such display"} }}
      fake: {info: $fake.INFO
             settings: {|given| fake settings $given }
             render-items: {|recs, s| fake render-items $recs $s }
             push-items: {|changed, removed, s| fake push-items $changed $removed $s }} }
}

def write-config [cfg: record] { $cfg | to yaml | save --force $CFG }
def log-lines []: nothing -> int {
    if ($LOG | path exists) { open --raw $LOG | lines | where {|l| $l | is-not-empty } | length } else { 0 }
}
def last-line []: nothing -> string { open --raw $LOG | lines | last }

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    mkdir $TMP
    $env.XDG_DATA_HOME = $TMP
    $env.AGENT_NOTIFY_CONFIG = $CFG

    # ── A. the config file ────────────────────────────────────────────────────
    let a = [
        (check "with no file at all, nothing is on" (config enabled) [])
        (check "…and that is not a problem" (config problems (displays)) [])
        (check "the path is the one we were told to use" (config file) $CFG)
    ]

    write-config {displays: ["fake"], fake: {log: $LOG}}
    let a2 = [
        (check "a good file is silent" (config problems (displays)) [])
        (check "…and says what is on" (config enabled) ["fake"])
        (check "config show reports where it read from"
               (agent-notify config show | get path) $CFG)
    ]

    write-config {displays: ["zellij"], fake: {log: $LOG}}
    let a3 = [
        (check "a display that does not exist is a typo, and is named"
               (config problems (displays) | length) 1)
        (check "…and the message says which one"
               (config problems (displays) | first | str contains "'zellij'") true)
    ]
    write-config {displays: ["fake"], colours: {working: "blue"}, fake: {log: $LOG}}
    let a4 = [
        (check "a top-level key that owns nothing is rejected"
               (config problems (displays) | first | str contains "'colours'") true)
    ]
    write-config {displays: "fake", fake: {log: $LOG}}
    let a5 = [
        (check "`displays` must be a list"
               (config problems (displays) | first | str contains "must be a list") true)
    ]
    write-config {displays: ["fake"], fake: "nope"}
    let a6 = [
        (check "a display's settings must be a map"
               (config problems (displays) | first | str contains "must be a map") true)
    ]

    # ── the two halves ────────────────────────────────────────────────────────
    # One tool, two unrelated jobs. What it SHOWS is pushed to it as events
    # arrive; what its COMMANDS do happens because you ran one. `displays:`
    # controls the first and says nothing about the second.
    let split = {displays: ["fake"]
                 fake: {log: $LOG, display: {glyphs: {working: "X"}}, commands: {query: "me"}}}
    write-config $split
    let a7 = [
        (check "a half is given what it owns, on top of what the tool shares"
               (config settings-for $split "fake" "display") {log: $LOG, glyphs: {working: "X"}})
        (check "…and the other half sees its own keys, never the first's"
               (config settings-for $split "fake" "commands") {log: $LOG, query: "me"})
        (check "a tool with nothing configured is not an error"
               (config settings-for {} "fake" "display") {})
        (check "…nor is a half it has nothing to say about"
               (config settings-for {fake: {log: $LOG}} "fake" "commands") {log: $LOG})
        # The whole reason the halves are split: a picker must not disappear
        # because you stopped wanting your panes renamed.
        (check "a tool that is NOT pushed to still has its commands configured"
               (config settings-for {fake: {commands: {query: "me"}}} "fake" "commands") {query: "me"})
        (check "a namespace that is not a map reads as nothing, rather than throwing"
               (config settings-for {fake: "nope"} "fake" "display") {})
        (check "a file using both halves is silent" (config problems (displays)) [])
    ]

    write-config {displays: ["fake"], fake: {log: $LOG, display: "nope"}}
    let a8 = [
        (check "a half that is not a map is named, half and all"
               (config problems (displays) | first | str contains "'fake.display'") true)
    ]

    # Only the TOOL knows what a key means, so the last check is its own
    # `settings` — which is what turns a typo into a sentence.
    write-config {displays: ["fake"], fake: {display: {}}}
    let a9 = [
        (check "a setting the tool rejects is reported in the tool's own words"
               (config problems (displays) | first | str contains "`log` is required") true)
        (check "…and says which tool and which half"
               (config problems (displays) | first | str starts-with "fake.display:") true)
    ]

    write-config {displays: [], fake: {display: {}}}
    let a10 = [
        (check "settings for a tool that is switched off are not a problem"
               (config problems (displays)) [])
    ]

    # ── B. the diff, which is the whole idea ──────────────────────────────────
    write-config {displays: ["fake"], fake: {log: $LOG}}

    let one = {id: "a1", agent: "claude", state: "working"}
    let two = {id: "a2", agent: "claude", state: "awaiting"}

    let b1 = dispatch repaint [] [$one] --table (displays)
    let b = [
        (check "a new agent is written" ($b1 | where display == "fake" | get action) ["applied"])
        (check "…one key" ($b1 | where display == "fake" | get wrote) [1])
        (check "…and the line says so" (last-line) "Wa1")
    ]

    # The whole point: a change the display cannot show must not reach it.
    let b2 = dispatch repaint [$one] [($one | upsert message "a long answer")] --table (displays)
    let b_gate = [
        (check "a change this display does not show is skipped"
               ($b2 | where display == "fake" | get action) ["skipped"])
        (check "…and nothing was written" (log-lines) 1)
    ]

    # And a change it CAN show reaches it — but only the key that moved.
    let b3 = dispatch repaint [$one $two] [($one | upsert state "awaiting") $two] --table (displays)
    let b_key = [
        (check "a state change is written" ($b3 | where display == "fake" | get action) ["applied"])
        (check "…and ONLY the agent that moved — not the one that did not"
               ($b3 | where display == "fake" | get wrote) [1])
        (check "…which is the one in the line" (last-line) "Aa1")
    ]

    let b4 = dispatch repaint [$one $two] [$one] --table (displays)
    let b_gone = [
        (check "an agent that vanished is undone, not merely forgotten"
               ($b4 | where display == "fake" | get undid) [1])
        (check "…and the undo names it" (last-line) "-a2")
    ]

    let n = log-lines
    let b5 = dispatch repaint [$one] [$one] --table (displays) --force
    let b_force = [
        (check "--force writes even when nothing moved"
               ($b5 | where display == "fake" | get action) ["applied"])
        (check "…and wrote again" (log-lines) ($n + 1))
    ]

    # ── C. what the config turns on, and failure isolation ────────────────────
    let before_off = log-lines
    write-config {displays: [], fake: {log: $LOG}}
    let c1 = dispatch repaint [] [$one] --table (displays)
    let c = [
        (check "a display not listed is never called" $c1 [])
        (check "…and wrote nothing" (log-lines) $before_off)
    ]

    write-config {displays: ["boom", "fake"], fake: {log: $LOG}}
    let c2 = dispatch repaint [] [$one] --table (displays) --force
    let c_iso = [
        (check "a display that throws is reported, not raised"
               ($c2 | where display == "boom" | get action) ["failed"])
        (check "…with its reason"
               ($c2 | where display == "boom" | get why | first | str contains "no such display") true)
        (check "…and the next display still runs"
               ($c2 | where display == "fake" | get action) ["applied"])
    ]

    write-config {displays: ["fake"], fake: {}}
    let c3 = dispatch repaint [] [$one] --table (displays) --force
    let c_settings = [
        (check "a display whose settings are wrong fails alone"
               ($c3 | where display == "fake" | get action) ["failed"])
        (check "…and says what it needed"
               ($c3 | first | get why | str contains "`log` is required") true)
    ]

    rm --force $CFG
    let c4 = dispatch repaint [] [$one] --table (displays)
    let c_nofile = [ (check "no config file means no displays, not an error" $c4 []) ]

    # ── D. the seam in operation.nu ───────────────────────────────────────────
    let d1 = operation apply {operation-kind: "patch", id: "d1", changes: {agent: "claude", state: "working"}}
    let d2 = operation apply {operation-kind: "end", id: "d1"}
    let d = [
        (check "a write still reports what it did" $d1.changed true)
        (check "dispatch cannot break a session-store write" ($d1.after.state) "working")
        (check "a drop carries what vanished, so a display can undo it"
               ($d2.before.id) "d1")
        (check "…and reports that it happened" $d2.changed true)
        (check "dropping nothing is still nothing"
               (operation apply {operation-kind: "end", id: "d1"} | get changed) false)
    ]

    # ── E. the halves reach the right place ───────────────────────────────────
    # The nesting is not decoration. What is under `display:` has to arrive in
    # the display's own `settings`, and what is under `commands:` must not.
    write-config {displays: ["fake"], fake: {log: $LOG, display: {glyphs: {working: "X"}}}}
    dispatch repaint [] [$one] --table (displays) --force | ignore
    let e1 = last-line
    write-config {displays: ["fake"], fake: {log: $LOG, commands: {glyphs: {working: "!"}}}}
    dispatch repaint [] [$one] --table (displays) --force | ignore
    let e = [
        (check "a setting under `display` reaches the display" $e1 "Xa1")
        (check "…and one under `commands` does not — the display keeps its default"
               (last-line) "Wa1")
    ]

    let all = ($a ++ $a2 ++ $a3 ++ $a4 ++ $a5 ++ $a6 ++ $a7 ++ $a8 ++ $a9 ++ $a10
               ++ $b ++ $b_gate ++ $b_key ++ $b_gone ++ $b_force
               ++ $c ++ $c_iso ++ $c_settings ++ $c_nofile ++ $d ++ $e)
    summarise $all --title "config + dispatch"
}
