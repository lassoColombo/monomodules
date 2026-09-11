# Step 3 — the config file and the dispatch gate.
#
# The gate is the whole point of this step, and section B is the part to read: a
# change that does not alter what a surface would show must not reach that
# surface. Everything here runs against a real store and a real config file, with
# `tests/fake.nu` standing in for zellij.

use ../../agent-notify2
use ../core/config.nu
use ../core/dispatch.nu
use ../core/event.nu
use fake.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-dispatch")
const LOG = ($nu.temp-dir | path join "agent-notify2-tests-dispatch" "surface.log")
const CFG = ($nu.temp-dir | path join "agent-notify2-tests-dispatch" "config.yaml")

# The shipped table's shape, built by hand — exactly what `core/dispatch.nu` will
# hold once zellij exists. `boom` is here to prove one surface cannot take another
# down with it.
def surfaces []: nothing -> record {
    { boom: {info: {name: "boom", title: "always fails"}
             settings: {|given| $given }
             project: {|recs, s| $recs | length }
             apply: {|desired, s| error make --unspanned {msg: "boom: no such display"} }}
      fake: {info: $fake.INFO
             settings: {|given| fake settings $given }
             project: {|recs, s| fake project $recs $s }
             apply: {|desired, s| fake apply $desired $s }} }
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
        (check "`surfaces` must be a list" (config problems ["fake"] | first | str contains "must be a list") true)
    ]
    write-config {surfaces: ["fake"], fake: "nope"}
    let a6 = [
        (check "a surface's settings must be a map"
               (config problems ["fake"] | first | str contains "must be a map") true)
    ]

    # ── B. the gate ──────────────────────────────────────────────────────────
    write-config {surfaces: ["fake"], fake: {log: $LOG}}

    let created = agent-notify2 store patch "a1" {client: "claude", state: "working"}
    let b1 = dispatch project $created.before $created.after --table (surfaces)
    let b = [
        (check "a new agent reaches the surface" ($b1 | where surface == "fake" | get action) ["applied"])
        (check "…once" (log-lines) 1)
        (check "…showing the state" (last-line) "Wa1")
    ]

    # The whole point: a turn that only changes the message must not repaint.
    let msg = agent-notify2 store patch "a1" {message: "a long answer"}
    let b2 = dispatch project $msg.before $msg.after --table (surfaces)
    let b_gate = [
        (check "the store did change" $msg.changed true)
        (check "…but the surface does not show messages, so it is skipped"
               ($b2 | where surface == "fake" | get action) ["skipped"])
        (check "…and nothing was written" (log-lines) 1)
    ]

    let moved = agent-notify2 store patch "a1" {state: "awaiting"}
    let b3 = dispatch project $moved.before $moved.after --table (surfaces)
    let b_move = [
        (check "a state change does repaint" ($b3 | where surface == "fake" | get action) ["applied"])
        (check "…with the new glyph" (last-line) "Aa1")
    ]

    let forced = dispatch project --force --table (surfaces)
    let b_force = [
        (check "--force repaints regardless" ($forced | where surface == "fake" | get action) ["applied"])
        (check "…and wrote again" (log-lines) 3)
    ]

    agent-notify2 store patch "a2" {client: "codex", state: "idle"} | ignore
    let gone = agent-notify2 store drop "a2"
    let b4 = dispatch project {id: "a2", client: "codex", state: "idle"} null --table (surfaces)
    let b_drop = [
        (check "an agent that vanished changes the picture"
               ($b4 | where surface == "fake" | get action) ["applied"])
        (check "…and is no longer in it" (last-line) "Aa1")
    ]

    # ── C. what the config turns on, and failure isolation ───────────────────
    let before_off = log-lines
    write-config {surfaces: [], fake: {log: $LOG}}
    let c1 = dispatch project $created.before $created.after --table (surfaces)
    let c = [
        (check "a surface not listed is never called" $c1 [])
        (check "…and wrote nothing" (log-lines) $before_off)
    ]

    write-config {surfaces: ["boom", "fake"], fake: {log: $LOG}}
    let c2 = dispatch project $moved.before $moved.after --table (surfaces) --force
    let c_iso = [
        (check "a surface that throws is reported, not raised"
               ($c2 | where surface == "boom" | get action) ["failed"])
        (check "…with its reason"
               ($c2 | where surface == "boom" | get why | first | str contains "no such display") true)
        (check "…and the next surface still runs"
               ($c2 | where surface == "fake" | get action) ["applied"])
    ]

    write-config {surfaces: ["fake"], fake: {}}
    let c3 = dispatch project $moved.before $moved.after --table (surfaces) --force
    let c_settings = [
        (check "a surface whose settings are wrong fails alone"
               ($c3 | where surface == "fake" | get action) ["failed"])
        (check "…and says what it needed"
               ($c3 | first | get why | str contains "`log` is required") true)
    ]

    rm --force $CFG
    let c4 = dispatch project $moved.before $moved.after --table (surfaces)
    let c_nofile = [ (check "no config file means no surfaces, not an error" $c4 []) ]

    # ── D. the seam in event.nu ──────────────────────────────────────────────
    # Nothing is shipped in `surfaces/` yet, so the link can only be proved the
    # other way round: the event path must be unchanged by dispatch existing.
    let d1 = event apply {op: "patch", id: "d1", changes: {client: "claude", state: "working"}}
    let d2 = event apply {op: "drop", id: "d1"}
    let d = [
        (check "a write still reports what it did" $d1.changed true)
        (check "dispatch cannot break a store write" ($d1.after.state) "working")
        (check "a drop now carries what vanished, so a surface can compare"
               ($d2.before.id) "d1")
        (check "…and reports that it happened" $d2.changed true)
        (check "dropping nothing is still nothing"
               (event apply {op: "drop", id: "d1"} | get changed) false)
    ]

    let all = ($a ++ $a2 ++ $a3 ++ $a4 ++ $a5 ++ $a6 ++ $b ++ $b_gate ++ $b_move
               ++ $b_force ++ $b_drop ++ $c ++ $c_iso ++ $c_settings ++ $c_nofile ++ $d)
    summarise $all --title "config + dispatch"
}
