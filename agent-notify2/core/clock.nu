# The clock: something that looks, periodically, when nobody else will.
#
# WHY THIS HAS TO EXIST. The store is PUSHED, never polled — an agent's hook
# writes it and paints the surfaces in the same breath, which is why a repaint
# costs 6.5ms and needs no daemon. But a dead agent fires no hook. That is what
# dead means. So an agent that is killed, or crashes, or has its pane closed,
# leaves a record nobody will ever revisit, and every surface keeps showing it.
#
# The tick is NOT a second pruning mechanism. It runs exactly the same
# `core/janitor.nu` prune — the pid one — and then repaints. All it contributes
# is the looking.
#
# WHY NOT `job spawn`. A nushell job is a thread inside the process that spawned
# it: it dies when that process exits, and so does anything it starts (both
# verified). A hook lives ~30ms, so nothing it spawns can be a clock.
#
# WHY NOT THE BAR. It worked — SketchyBar's daemon is already running and an item
# with `update_freq=30` is free — but it made a core guarantee depend on one
# optional surface being installed and enabled. Turn the bar off and dead agents
# accumulate silently.
#
# The exports are `arm` / `disarm` / `check` / `tick` rather than the obvious
# install / uninstall / status / command, because `cli/clock.nu` publishes those
# as `clock install` and friends — and a command calling the name it is defining
# calls itself. Third time that rule has bitten (plan.md §10).
#
# SO: launchd, which IS a clock. `StartInterval` means there is no daemon to keep
# alive, no lock file, no pid to supervise, and no detaching trick — launchd
# starts a nu, it prunes and repaints, it exits. It survives logout and reboot,
# which a spawned process would not.

export const LABEL = "com.agent-notify.clock"

const SELF = path self

export def plist-path []: nothing -> string {
    $nu.home-dir | path join "Library" "LaunchAgents" $"($LABEL).plist"
}

def module-root []: nothing -> string { $SELF | path dirname | path dirname }

export def log-path []: nothing -> string {
    let base = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join ".local" "state")
    $base | path join "agent-notify" "clock.log"
}

# The tick itself is just `surfaces refresh`: prune what is provably gone, then
# repaint whatever is left. Nothing here that a human could not type.
export def tick []: nothing -> list<string> {
    [ $nu.current-exe "-n" "--no-std-lib" "-c" $"use (module-root); agent-notify2 surfaces refresh" ]
}

export def plist [interval: int]: nothing -> string {
    let args = tick | each {|a| $"        <string>($a)</string>" } | str join "\n"
    ([ '<?xml version="1.0" encoding="UTF-8"?>'
       '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
       '<plist version="1.0">'
       '<dict>'
       '    <key>Label</key>'
       $"    <string>($LABEL)</string>"
       '    <key>ProgramArguments</key>'
       '    <array>'
       $args
       '    </array>'
       '    <key>StartInterval</key>'
       $"    <integer>($interval)</integer>"
       '    <key>RunAtLoad</key>'
       '    <true/>'
       '    <key>StandardErrorPath</key>'
       $"    <string>(log-path)</string>"
       '</dict>'
       '</plist>' ] | str join "\n")
}

def domain []: nothing -> string { $"gui/(^id -u | str trim)" }

export def arm [interval: int]: nothing -> record {
    let f = plist-path
    mkdir ($f | path dirname)
    mkdir (log-path | path dirname)
    plist $interval | save --force $f

    # `bootout` first so re-installing picks up a changed interval or path. It
    # fails when nothing is loaded, which is the normal case and not an error.
    ^launchctl bootout $"(domain)/($LABEL)" | complete | ignore
    let r = ^launchctl bootstrap (domain) $f | complete
    { path: $f, interval: $interval, loaded: ($r.exit_code == 0)
      why: (if ($r.exit_code == 0) { "" } else { $r.stderr | str trim }) }
}

export def disarm []: nothing -> record {
    let f = plist-path
    ^launchctl bootout $"(domain)/($LABEL)" | complete | ignore
    let existed = $f | path exists
    if $existed { rm --force $f }
    {removed: $existed, path: $f}
}

# Loaded or not, and what it last did. `launchctl list` gives the pid (or `-` when
# it is between runs) and the last exit status, which is how a broken tick is
# noticed rather than silently doing nothing every 30 seconds.
export def check []: nothing -> record {
    let r = ^launchctl list | complete
    let line = if ($r.exit_code == 0) {
        $r.stdout | lines | where {|l| $l | str ends-with $LABEL } | get -o 0
    } else { null }
    let f = ($r.exit_code == 0) and ($line != null)
    let fields = if $f { $line | str trim | split row --regex '\s+' } else { [] }
    { label: $LABEL
      installed: (plist-path | path exists)
      loaded: $f
      last_exit: (if $f { $fields.1 } else { "" })
      running_now: (if $f and ($fields.0 != "-") { true } else { false })
      interval: (if (plist-path | path exists) {
            let m = open --raw (plist-path) | lines | enumerate
                  | where {|l| $l.item | str contains "<key>StartInterval</key>" } | get -o 0
            if $m == null { 0 } else {
                open --raw (plist-path) | lines | get ($m.index + 1) | str trim
                | str replace --all --regex '</?integer>' '' | into int
            }
        } else { 0 })
      log: (log-path) }
}
