# Step 3, rewritten for the contract of step 7b — the config file, and the diff.
#
# The section to read is B. A surface says what should be shown, as a map; this is
# where "what changed" is worked out, once, for every surface that will ever
# exist. Everything here runs against a real store and a real config file, with
# `tests/fake.nu` standing in for zellij.

use ../../agent-notify2
use ../core/config.nu
use ../core/dispatch.nu
use ../core/event.nu
use ../core/store.nu
use fake.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-dispatch")
const LOG = ($nu.temp-dir | path join "agent-notify2-tests-dispatch" "surface.log")
const CFG = ($nu.temp-dir | path join "agent-notify2-tests-dispatch" "config.yaml")

# The shipped table's shape, by hand — exactly what `core/dispatch.nu` holds.
# `boom` proves one surface cannot take another down with it.
def surfaces []: nothing -> record {
    { boom: {info: {name: "boom", title: "always fails"}
             settings: {|given| $given }
             project: {|recs, s| {all: ($recs | length)} }
             apply: {|changed, removed, s| error make --unspanned {msg: "boom: no such display"} }}
      fake: {info: $fake.INFO
             settings: {|given| fake settings $given }
             project: {|recs, s| fake project $recs $s }
             apply: {|changed, removed, s| fake apply $changed $removed $s }} }
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

    # ── A. the config file ───────────────────────────────────────────────────
    let a = [
        (check "with no file at all, nothing is on" (config enabled) [])
        (check "…and that is not a problem" (config problems ["fake"]) [])
        (check "the path is the one we were told to use" (config file) $CFG)
    ]

    write-config {surfaces: ["fake"], fake: {log: $LOG}}
    let a2 = [
        (check "a good file is silent" (config problems ["fake" "boom"]) [])
        (check "…and says what is on" (config enabled) ["fake"])
        (check "config show reports where it read from"
               (agent-notify2 config show | get path) $CFG)
    ]

    write-config {surfaces: ["zellij"], fake: {log: $LOG}}
    let a3 = [
        (check "a surface that does not exist is a typo, and is named"
               (config problems ["fake"] | length) 1)
        (check "…and the message says which one"
               (config problems ["fake"] | first | str contains "'zellij'") true)
    ]
    write-config {surfaces: ["fake"], colours: {working: "blue"}, fake: {log: $LOG}}
    let a4 = [
        (check "a top-level key that owns nothing is rejected"
               (config problems ["fake"] | first | str contains "'colours'") true)
    ]
    write-config {surfaces: "fake", fake: {log: $LOG}}
    let a5 = [
        (check "`surfaces` must be a list"
               (config problems ["fake"] | first | str contains "must be a list") true)
    ]
    write-config {surfaces: ["fake"], fake: "nope"}
    let a6 = [
        (check "a surface's settings must be a map"
               (config problems ["fake"] | first | str contains "must be a map") true)
    ]

    # ── B. the diff, which is the whole idea ─────────────────────────────────
    write-config {surfaces: ["fake"], fake: {log: $LOG}}

    let one = {id: "a1", client: "claude", state: "working"}
    let two = {id: "a2", client: "claude", state: "awaiting"}

    let b1 = dispatch project [] [$one] --table (surfaces)
    let b = [
        (check "a new agent is written" ($b1 | where surface == "fake" | get action) ["applied"])
        (check "…one key" ($b1 | where surface == "fake" | get wrote) [1])
        (check "…and the line says so" (last-line) "Wa1")
    ]

    # The whole point: a change the surface cannot show must not reach it.
    let b2 = dispatch project [$one] [($one | upsert message "a long answer")] --table (surfaces)
    let b_gate = [
        (check "a change this surface does not show is skipped"
               ($b2 | where surface == "fake" | get action) ["skipped"])
        (check "…and nothing was written" (log-lines) 1)
    ]

    # And a change it CAN show reaches it — but only the key that moved.
    let b3 = dispatch project [$one $two] [($one | upsert state "awaiting") $two] --table (surfaces)
    let b_key = [
        (check "a state change is written" ($b3 | where surface == "fake" | get action) ["applied"])
        (check "…and ONLY the agent that moved — not the one that did not"
               ($b3 | where surface == "fake" | get wrote) [1])
        (check "…which is the one in the line" (last-line) "Aa1")
    ]

    let b4 = dispatch project [$one $two] [$one] --table (surfaces)
    let b_gone = [
        (check "an agent that vanished is undone, not merely forgotten"
               ($b4 | where surface == "fake" | get undid) [1])
        (check "…and the undo names it" (last-line) "-a2")
    ]

    let n = log-lines
    let b5 = dispatch project [$one] [$one] --table (surfaces) --force
    let b_force = [
        (check "--force writes even when nothing moved"
               ($b5 | where surface == "fake" | get action) ["applied"])
        (check "…and wrote again" (log-lines) ($n + 1))
    ]

    # ── C. what the config turns on, and failure isolation ───────────────────
    let before_off = log-lines
    write-config {surfaces: [], fake: {log: $LOG}}
    let c1 = dispatch project [] [$one] --table (surfaces)
    let c = [
        (check "a surface not listed is never called" $c1 [])
        (check "…and wrote nothing" (log-lines) $before_off)
    ]

    write-config {surfaces: ["boom", "fake"], fake: {log: $LOG}}
    let c2 = dispatch project [] [$one] --table (surfaces) --force
    let c_iso = [
        (check "a surface that throws is reported, not raised"
               ($c2 | where surface == "boom" | get action) ["failed"])
        (check "…with its reason"
               ($c2 | where surface == "boom" | get why | first | str contains "no such display") true)
        (check "…and the next surface still runs"
               ($c2 | where surface == "fake" | get action) ["applied"])
    ]

    write-config {surfaces: ["fake"], fake: {}}
    let c3 = dispatch project [] [$one] --table (surfaces) --force
    let c_settings = [
        (check "a surface whose settings are wrong fails alone"
               ($c3 | where surface == "fake" | get action) ["failed"])
        (check "…and says what it needed"
               ($c3 | first | get why | str contains "`log` is required") true)
    ]

    rm --force $CFG
    let c4 = dispatch project [] [$one] --table (surfaces)
    let c_nofile = [ (check "no config file means no surfaces, not an error" $c4 []) ]

    # ── D. the seam in event.nu ──────────────────────────────────────────────
    let d1 = event apply {op: "patch", id: "d1", changes: {client: "claude", state: "working"}}
    let d2 = event apply {op: "drop", id: "d1"}
    let d = [
        (check "a write still reports what it did" $d1.changed true)
        (check "dispatch cannot break a store write" ($d1.after.state) "working")
        (check "a drop carries what vanished, so a surface can undo it"
               ($d2.before.id) "d1")
        (check "…and reports that it happened" $d2.changed true)
        (check "dropping nothing is still nothing"
               (event apply {op: "drop", id: "d1"} | get changed) false)
    ]

    let all = ($a ++ $a2 ++ $a3 ++ $a4 ++ $a5 ++ $a6 ++ $b ++ $b_gate ++ $b_key
               ++ $b_gone ++ $b_force ++ $c ++ $c_iso ++ $c_settings ++ $c_nofile ++ $d)
    summarise $all --title "config + dispatch"
}
