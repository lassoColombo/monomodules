# Step 4c — proving an agent is gone.
#
# This suite can be honest about liveness because it is itself a process: it uses
# its OWN pid as the known-alive case, and a process it starts and lets finish as
# the known-dead one. Nothing here depends on which agent is running the tests, or
# on any agent running at all.
#
# The two rules being tested are in core/janitor.nu, and the second matters more
# than the first: not knowing that an agent is dead must never become deleting it.

use ../../agent-notify2
use ../core/proc.nu
use ../core/janitor.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-proc")

# A pid that is certainly gone: bash prints its own, then exits.
def dead-pid []: nothing -> int { ^bash -c 'echo $$' | str trim | into int }

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # surface on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")
    hide-env --ignore-errors AGENT_NOTIFY_PID

    let me = proc find "nu"
    let gone = dead-pid

    # ── finding the process ──────────────────────────────────────────────────
    let a = [
        (check "walking up finds a process by name — ours is nu" $me.pid $nu.pid)
        (check "…and records when it started" (($me.started | str length) > 10) true)
        (check "a name nothing is running is not invented" (proc find "no-such-program-xyz") null)
        (check "an empty name finds nothing rather than guessing" (proc find "") null)
    ]

    $env.AGENT_NOTIFY_PID = ($nu.pid | into string)
    let told = proc find "no-such-program-xyz"
    let b = [
        (check "an agent that exports its own pid skips the walk entirely" $told.pid $nu.pid)
        (check "…and is believed over the name" ($told != null) true)
    ]
    $env.AGENT_NOTIFY_PID = ($gone | into string)
    let c = [ (check "a pid that exports a lie is not turned into a fact"
                     (proc find "no-such-program-xyz") null) ]
    hide-env AGENT_NOTIFY_PID

    # ── liveness ─────────────────────────────────────────────────────────────
    let d = [
        (check "we are alive" (proc living [$me]) [$nu.pid])
        (check "a finished process is not" (proc living [{pid: $gone, started: "whenever"}]) [])
        (check "the living are told from the dead in one answer"
               (proc living [$me {pid: $gone, started: "whenever"}]) [$nu.pid])
        (check "a RECYCLED pid is not our process: same number, wrong start time"
               (proc living [{pid: $nu.pid, started: "Fri Jan  1 00:00:00 2000"}]) [])
        (check "nothing to ask about is an empty answer, not an error" (proc living []) [])
    ]

    # ── the janitor ──────────────────────────────────────────────────────────
    agent-notify2 store patch "alive-1" {client: "claude", state: "working", proc: $me} | ignore
    agent-notify2 store patch "dead-1" {client: "claude", state: "working"
                                        proc: {pid: $gone, started: "whenever"}} | ignore
    agent-notify2 store patch "untracked-1" {client: "claude", state: "awaiting"} | ignore

    let dropped = janitor prune
    let left = agent-notify2 store list | get id | sort
    let e = [
        (check "the agent whose process is gone is dropped" ($dropped | get id) ["dead-1"])
        (check "…and says why" ($dropped | first | get why) "process gone")
        (check "the live one survives" ("alive-1" in $left) true)
        (check "an agent with NO recorded process is never touched — no proof, no deletion"
               ("untracked-1" in $left) true)
        (check "nothing else was removed" $left ["alive-1" "untracked-1"])
        (check "pruning again finds nothing to do" (janitor prune) [])
    ]

    # ── /clear: one live process, two records ────────────────────────────────
    # The same agent started a fresh session in the same process. The older record
    # is finished, even though its pid is genuinely alive.
    agent-notify2 store patch "cleared-old" {client: "claude", state: "awaiting", proc: $me} | ignore
    agent-notify2 store patch "cleared-new" {client: "claude", state: "working", proc: $me} | ignore
    let dropped2 = janitor prune
    let left2 = agent-notify2 store list | get id | sort
    let f = [
        (check "among records sharing one live pid, the older ones go"
               ($dropped2 | get id | sort) ["alive-1" "cleared-old"])
        (check "…for a reason that is not death" ($dropped2 | first | get why | str contains "superseded") true)
        (check "the newest survives" ("cleared-new" in $left2) true)
        (check "and the untracked one is still none of our business" ("untracked-1" in $left2) true)
    ]

    summarise ($a ++ $b ++ $c ++ $d ++ $e ++ $f) --title "process liveness"
}
