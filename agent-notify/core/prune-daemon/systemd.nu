# systemd — the Linux launcher. A USER timer, never a system one.
#
# Two files where launchd needs one, because systemd separates what to run from
# when to run it: a `oneshot` service that does the tick, and a timer that says
# how often. They are linked by name, and `Unit=` says so anyway for whoever
# reads the file.
#
# ── ACCURACYSEC, WHICH IS NOT OPTIONAL HERE ───────────────────────────────────
# `AccuracySec=` defaults to ONE MINUTE, and the default would quietly make
# `--interval 30` a lie. From systemd.timer(5):
#
#   "The timer is scheduled to elapse within a time window starting with the
#    time specified in OnUnitActiveSec= … and ending the time configured with
#    AccuracySec= later. Within this time window, the expiry time will be placed
#    at a host-specific, randomized, but STABLE position that is SYNCHRONIZED
#    BETWEEN ALL LOCAL TIMER UNITS."
#
# Stable and synchronized, not jitter. Every timer on the machine lands on one
# shared grid, and with the default that grid is a minute wide. Follow a 30s
# timer through it: fire at T, next elapse computed at T+30, window [T+30, T+90],
# which contains exactly ONE point of a 60s grid. So it fires there, and the next
# window contains the next grid point. Steady state: a 30-second timer that fires
# every 60 seconds, consistently, forever.
#
# So we set it, to 1s, for one reason: so that `install launchd --interval 30`
# and `install systemd --interval 30` MEAN THE SAME THING. If the two launchers
# disagree about what the number means, the abstraction is not one. The cost is
# honest and small — our timer opts out of wake-up batching, one un-batched
# wakeup per interval on a machine that is by definition running a coding agent
# at the time. systemd suggests 1us for maximum precision and warns against going
# too low as a power matter; 1s is well clear of that and a hundred times finer
# than anything here needs.
#
# AND IT IS A PER-UNIT SETTING, in the `[Timer]` section of the file below. The
# global knob is a different setting with a different name —
# `DefaultTimerAccuracySec=` in `systemd/user.conf` — and this module never goes
# near it. See mod.nu on what a launcher may touch.
#
# Two settings deliberately NOT set, for the same reason: `WakeSystem=` (defaults
# false — waking a sleeping laptop to prune is not worth it) and
# `RandomizedDelaySec=` (defaults 0 — nothing to gain).
#
# ── WHAT IS NOT YET VERIFIED ON REAL HARDWARE ─────────────────────────────────
# What happens after the machine sleeps through several intervals. launchd fires
# once on wake; this is written expecting systemd to do the same, and it belongs
# in plan.md §11 only once someone has watched it. `Persistent=` would not help
# either way — it applies to `OnCalendar=`, not to monotonic timers.

export const INFO = {name: "systemd", title: "Linux — a user timer with OnUnitActiveSec"}
export const UNIT = "agent-notify-prune-daemon"

def unit-dir []: nothing -> string {
    let base = $env.XDG_CONFIG_HOME? | default ($nu.home-dir | path join ".config")
    $base | path join "systemd" "user"
}

export def service-path []: nothing -> string { unit-dir | path join $"($UNIT).service" }
export def timer-path []: nothing -> string { unit-dir | path join $"($UNIT).timer" }

# The binary existing is not the question — WSL1 and plenty of containers ship
# `systemctl` with no user manager behind it. `--user list-units` is the probe
# that fails in exactly that case, because it needs the user bus that everything
# else here needs too.
export def available []: nothing -> record {
    if (which systemctl | is-empty) {
        return {ok: false, why: $"systemctl is not on PATH \(this machine is ($nu.os-info.name))"}
    }
    let r = ^systemctl --user list-units --no-legend --no-pager | complete
    if $r.exit_code != 0 {
        let said = $r.stderr | str trim | lines | first 1 | str join ""
        return {ok: false, why: $"`systemctl --user` cannot reach a user manager: ($said)"}
    }
    {ok: true, why: ""}
}

# ── quoting ───────────────────────────────────────────────────────────────────
# `%` is a SPECIFIER, expanded in EVERY value in a unit file before anything else
# happens, so a literal one has to be doubled wherever it appears — a home
# directory with a `%` in it would otherwise turn into something else entirely.
def literal [a: string]: nothing -> string { $a | str replace --all '%' '%%' }

# ExecStart is a command LINE, and that is a second layer: systemd splits it on
# whitespace and honours quotes with C-style escapes inside them, so every
# argument is wrapped and every backslash and double quote escaped. A path in
# `StandardError=append:` is NOT a command line — quoting it would make the
# quotes part of the filename — so it gets `literal` alone.
def quote [a: string]: nothing -> string {
    let e = $a
          | str replace --all '\' '\\'
          | str replace --all '"' '\"'
    $'"(literal $e)"'
}

# PURE. Two files, and every argument of the tick reaches ExecStart verbatim.
export def unit-files [tick: list<string>, log: string, interval: int]: nothing -> table {
    let exec = $tick | each {|a| quote $a } | str join " "

    let service = ([ '[Unit]'
       'Description=agent-notify — sweep sessions whose process is gone, then repaint'
       ''
       '[Service]'
       'Type=oneshot'
       $"ExecStart=($exec)"
       # The same log file the launchd job writes, so `status` reports one path
       # whichever launcher is running and a broken tick is noticed the same way
       # on both. journald still has the unit; this is the copy we promise.
       $"StandardError=append:(literal $log)"
       '' ] | str join "\n")

    let timer = ([ '[Unit]'
       $"Description=agent-notify — look for dead agents every ($interval)s"
       ''
       '[Timer]'
       # The RunAtLoad equivalent: fire promptly when the timer is enabled,
       # rather than one whole interval later.
       'OnActiveSec=1s'
       $"OnUnitActiveSec=($interval)s"
       'AccuracySec=1s'
       $"Unit=($UNIT).service"
       ''
       '[Install]'
       'WantedBy=timers.target'
       '' ] | str join "\n")

    [{path: (service-path), text: $service}
     {path: (timer-path), text: $timer}]
}

# `daemon-reload` first, or systemd runs the file it read last time — which on a
# re-install is the OLD interval, with no complaint. `enable --now` both starts
# the timer and makes it come back at the next login.
export def register []: nothing -> record {
    ^systemctl --user daemon-reload | complete | ignore
    let r = ^systemctl --user enable --now $"($UNIT).timer" | complete
    {ok: ($r.exit_code == 0), why: (if ($r.exit_code == 0) { "" } else { $r.stderr | str trim })}
}

# `disable --now` stops the timer and removes the symlink `enable` made — which
# lives outside our two files, and is the one thing deleting them would leave
# behind. The `daemon-reload` after is for the files mod.nu is about to remove.
export def unregister []: nothing -> record {
    let r = ^systemctl --user disable --now $"($UNIT).timer" | complete
    ^systemctl --user daemon-reload | complete | ignore
    {ok: ($r.exit_code == 0), why: (if ($r.exit_code == 0) { "" } else { $r.stderr | str trim })}
}

# `show` answers for a unit that does not exist too, which is why `installed` is
# the file on disk and not systemd's opinion. `ExecMainStatus` on the SERVICE is
# the last tick's exit code — the timer only ever reports on itself.
export def status []: nothing -> record {
    let t = show-of $"($UNIT).timer" ["ActiveState" "UnitFileState"]
    let s = show-of $"($UNIT).service" ["ActiveState" "ExecMainStatus"]
    { installed: ((service-path | path exists) and (timer-path | path exists))
      loaded: (($t | get -o ActiveState) == "active")
      last_exit: ($s | get -o ExecMainStatus | default "")
      running_now: (($s | get -o ActiveState) in ["active" "activating"])
      interval: (interval-in-file) }
}

# `show -p a -p b` prints `KEY=VALUE` lines, one per property, and exits 0 even
# for a unit that was never installed — the values just come back empty.
def show-of [unit: string, props: list<string>]: nothing -> record {
    let flags = $props | each {|p| ["-p" $p] } | flatten
    let r = ^systemctl --user show $unit ...$flags | complete
    if $r.exit_code != 0 { return {} }
    $r.stdout | lines | reduce --fold {} {|l, acc|
        let kv = $l | split row --number 2 "="
        if ($kv | length) < 2 { $acc } else { $acc | upsert $kv.0 $kv.1 }
    }
}

# Read the interval back OUT of the timer file, for the same reason launchd reads
# it out of the plist: the file is what systemd obeys.
def interval-in-file []: nothing -> int {
    let f = timer-path
    if not ($f | path exists) { return 0 }
    let line = open --raw $f | lines | where {|l| $l | str starts-with "OnUnitActiveSec=" } | get -o 0
    if $line == null { return 0 }
    let v = $line | str replace "OnUnitActiveSec=" "" | str trim | str replace --all "s" ""
    try { $v | into int } catch { 0 }
}
