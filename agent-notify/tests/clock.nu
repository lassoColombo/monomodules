# The clock — the periodic look that notices agents nobody will report.
#
# Only the pure half is exercised here: what the tick would run, and what the
# launchd job would say. `arm` and `disarm` talk to launchctl and would load a
# real job on the machine running the tests, which a test must never do.

use ../../agent-notify
use ../core/clock.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-clock")

export def main [] {
    $env.XDG_STATE_HOME = $TMP

    let tick = clock tick
    let p = clock plist 45

    let a = [
        (check "the tick is the same refresh a human can type"
               ($tick | last | str contains "agent-notify surfaces refresh") true)
        (check "…which prunes first and paints second, so one mechanism does both"
               ($tick | any {|x| $x | str contains "surfaces refresh" }) true)
        (check "it names nu by absolute path — a launchd job has no PATH of yours"
               ($tick | first | str starts-with "/") true)
        (check "…and starts it with no config, like every other entry point"
               ("--no-std-lib" in $tick) true)
        (check "the job is named once, and recognisably"
               $clock.LABEL "com.agent-notify.clock")
    ]

    let b = [
        (check "the plist asks launchd for the interval we gave it"
               ($p | str contains "<integer>45</integer>") true)
        (check "…and to run once at load, so installing it takes effect immediately"
               ($p | str contains "<key>RunAtLoad</key>") true)
        (check "every argument of the tick reaches the job"
               ($tick | all {|a| $p | str contains $a }) true)
        (check "a failing tick leaves a trace instead of failing in silence"
               ($p | str contains "StandardErrorPath") true)
        (check "the log follows XDG_STATE_HOME"
               (clock log-path | str starts-with $TMP) true)
        (check "the job lives where launchd looks for user agents"
               (clock plist-path | str contains "Library/LaunchAgents") true)
    ]

    # The guard runs before launchctl is touched, so this is safe to assert.
    let c = [
        (check-err "an interval that would be a busy loop is refused"
                   "busy loop" {|| agent-notify clock install --interval 5 })
    ]

    summarise ($a ++ $b ++ $c) --title "clock"
}
