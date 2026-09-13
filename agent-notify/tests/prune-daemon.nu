# The prune-daemon — the periodic look that notices agents nobody will report.
#
# Only the pure half is exercised: what the tick would run, and what each
# launcher would WRITE. `register` and `unregister` talk to launchctl and
# systemctl and would load a real job on the machine running the tests, which a
# test must never do.
#
# WHICH IS WHY `unit-files` IS PURE (D66): the systemd timer below is asserted in
# full from a Mac, on a machine with no systemd on it at all. That is the whole
# reason the contract puts the file text on one side of a line and the subprocess
# on the other.
#
# The refusals ARE exercised, because every one of them fires before anything is
# written or any launcher is spoken to.

use ../../agent-notify
use ../core/prune-daemon
use ../core/prune-daemon/launchd.nu
use ../core/prune-daemon/systemd.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-prune-daemon")

export def main [] {
    $env.XDG_STATE_HOME = $TMP

    let tick = prune-daemon prune-command
    let log = prune-daemon log-path

    let a = [
        (check "the tick is the same refresh a human can type"
               ($tick | last | str contains "agent-notify displays refresh") true)
        (check "…which sweeps first and paints second, so one mechanism does both"
               ($tick | any {|x| $x | str contains "displays refresh" }) true)
        (check "it names nu by absolute path — a launcher has no PATH of yours"
               ($tick | first | str starts-with "/") true)
        (check "…and starts it with no config, like every other entry point"
               ("--no-std-lib" in $tick) true)
        (check "the log follows XDG_STATE_HOME"
               ($log | str starts-with $TMP) true)
        (check "…and is the same log whichever launcher is running"
               (prune-daemon status-of-job | get log | uniq | length) 1)
    ]

    # ── the registry ─────────────────────────────────────────────────────────
    let b = [
        (check "there are two launchers, named"
               (prune-daemon launcher-registry-names) ["launchd" "systemd"])
        (check "each one describes itself for the completion menu"
               (prune-daemon launcher-registry | values | all {|l| $l.info.title | is-not-empty }) true)
        (check "status answers for every launcher, not just the one that works here"
               (prune-daemon status-of-job | get launcher) ["launchd" "systemd"])
        (check "…and says WHY the ones that cannot run here cannot"
               (prune-daemon status-of-job | where available == false | all {|r| $r.why | is-not-empty }) true)
    ]

    # ── launchd ──────────────────────────────────────────────────────────────
    let p = prune-daemon unit-files "launchd" 45 | get 0
    let c = [
        (check "launchd wants exactly one file"
               (prune-daemon unit-files "launchd" 45 | length) 1)
        (check "the job is named once, and recognisably"
               $launchd.LABEL "com.agent-notify.prune-daemon")
        (check "the plist asks launchd for the interval we gave it"
               ($p.text | str contains "<integer>45</integer>") true)
        (check "…and to run once at load, so installing it takes effect immediately"
               ($p.text | str contains "<key>RunAtLoad</key>") true)
        (check "every argument of the tick reaches the job"
               ($tick | all {|a| $p.text | str contains $a }) true)
        (check "a failing tick leaves a trace instead of failing in silence"
               ($p.text | str contains $"<string>($log)</string>") true)
        (check "the job lives where launchd looks for user agents"
               ($p.path | str contains "Library/LaunchAgents") true)
        (check "launchd is available here and only here"
               (launchd available | get ok) ($nu.os-info.name == "macos"))
    ]

    # ── systemd ──────────────────────────────────────────────────────────────
    # Asserted in full on whatever machine runs the tests, systemd or not.
    let u = prune-daemon unit-files "systemd" 45
    let svc = $u | where {|f| $f.path | str ends-with ".service" } | get 0
    let tmr = $u | where {|f| $f.path | str ends-with ".timer" } | get 0
    let d = [
        (check "systemd wants two files — what to run, and when"
               ($u | length) 2)
        (check "both live under the USER unit directory, never a system one"
               ($u | all {|f| $f.path | str contains ".config/systemd/user" }) true)
        (check "…and both are named after us, so uninstall can be sure what is ours"
               ($u | all {|f| ($f.path | path basename) | str starts-with $systemd.UNIT }) true)
        (check "the service runs once and exits, like the launchd job does"
               ($svc.text | str contains "Type=oneshot") true)
        (check "every argument of the tick reaches ExecStart"
               ($tick | all {|a| $svc.text | str contains $a }) true)
        (check "…each one quoted, because systemd splits a command line on spaces"
               ($svc.text | str contains $'ExecStart="($tick | first)" "-n"') true)
        (check "a failing tick lands in the same log the launchd job writes"
               ($svc.text | str contains $"StandardError=append:($log)") true)
        (check "the timer asks for the interval we gave it"
               ($tmr.text | str contains "OnUnitActiveSec=45s") true)
        (check "…and fires promptly on enable, the RunAtLoad equivalent"
               ($tmr.text | str contains "OnActiveSec=1s") true)
        # The one that would otherwise be a silent lie: without this line a 30s
        # timer lands on the shared 1-minute coalescing grid and ticks every 60s.
        (check "ACCURACYSEC IS PINNED, or the interval means something else here"
               ($tmr.text | str contains "AccuracySec=1s") true)
        (check "…and it is set on OUR timer, never on the machine's defaults"
               ($u | any {|f| $f.text | str contains "DefaultTimerAccuracySec" }) false)
        (check "nothing wakes a sleeping machine to prune"
               ($tmr.text | str contains "WakeSystem") false)
        (check "the timer can be enabled, so it comes back at the next login"
               ($tmr.text | str contains "WantedBy=timers.target") true)
        (check "systemd is not available on macOS"
               (if ($nu.os-info.name == "macos") { systemd available | get ok } else { false }) false)
    ]

    # ── the refusals, every one of them before anything is written ───────────
    let other = if ($nu.os-info.name == "macos") { "systemd" } else { "launchd" }
    let e = [
        (check-err "an interval that would be a busy loop is refused"
                   "busy loop" {|| agent-notify prune-daemon install launchd --interval 5 })
        (check-err "a launcher that does not exist is refused, with the ones that do"
                   "try: launchd, systemd" {|| agent-notify prune-daemon install lolcat })
        (check-err "a launcher this machine cannot run is refused BY NAME"
                   $"($other) cannot run here" {|| agent-notify prune-daemon install $other })
        (check-err "…and says what it probed, not what the launcher's stderr said"
                   "not on PATH" {|| agent-notify prune-daemon install $other })
    ]

    summarise ($a ++ $b ++ $c ++ $d ++ $e) --title "prune-daemon"
}
