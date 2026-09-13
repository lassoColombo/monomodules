# The prune-daemon: something that looks, periodically, when nobody else will.
#
# WHY THIS HAS TO EXIST. The session-store is PUSHED, never polled — an agent's
# hook writes it and paints the displays in the same breath, which is why a
# repaint costs 6.5ms and needs no daemon. But a dead agent fires no hook. That
# is what dead means. So an agent that is killed, or crashes, or has its pane
# closed, leaves a record nobody will ever revisit, and every display keeps
# showing it.
#
# The tick is NOT a second pruning mechanism. It runs exactly the same
# `core/store-garbage-collector.nu` sweep — the pid one — and then repaints. All
# it contributes is the looking.
#
# WHY NOT `job spawn`. A nushell job is a thread inside the process that spawned
# it: it dies when that process exits, and so does anything it starts (both
# verified, again on 0.115.1). nushell has no `disown` and no way to detach a
# process — "spawn an independent background process" is an open design question
# upstream, hard on Windows because there is no `fork`. A hook lives ~30ms, so
# nothing it spawns can still be running a minute later.
#
# WHY NOT THE BAR. It worked — SketchyBar's daemon is already running and an
# item with `update_freq=30` is free — but it made a core guarantee depend on
# one optional display being installed and enabled. Turn the bar off and dead
# agents accumulate silently.
#
# SO: A LAUNCHER THE MACHINE ALREADY RUNS. There is no daemon to keep alive, no
# lock file, no pid to supervise, and no detaching trick — the launcher starts a
# nu, it prunes and repaints, it exits. It survives logout and reboot, which a
# spawned process would not.
#
# ── WHY THERE IS MORE THAN ONE ────────────────────────────────────────────────
# nushell is cross-platform and launchd is not, so the ONE genuinely
# platform-locked thing in `core/` became a table (D66). Two launchers today,
# and each is the same four questions:
#
#   INFO         what it is, for `agent-notify prune-daemon status`
#   available    CAN this launcher run here? A PROBE, not a guess — the binary
#                and, for systemd, a user manager that actually answers. It
#                returns {ok, why}, and `why` is shown to the user verbatim,
#                because a refusal is the whole of the UX for a choice they made.
#   unit-files   PURE: (tick, log, interval) → the files to write, as
#                {path, text}. Nothing is written and no subprocess runs, which
#                is what lets `tests/prune-daemon.nu` assert a systemd timer from
#                a Mac — and what `prune-daemon unit <launcher>` prints.
#   register     load the files just written. `unregister` is its undo.
#   status       installed / loaded / last exit / the interval read back OUT of
#                the unit file, because the file is the truth and not what
#                someone typed once.
#
# ── AND WHY NOTHING AUTODETECTS ───────────────────────────────────────────────
# `prune-daemon install` takes the launcher as a REQUIRED argument (D67). The
# machine is not asked. Autodetection would be right ~always and invisible when
# wrong — and wrong looks exactly like "dead agents linger", with nothing in any
# log. So the user names it, the completer offers the two with a description
# each, and `available` turns from a chooser into a VALIDATOR whose error names
# what it probed and what to try instead.
#
# THE ASYMMETRY IS DELIBERATE: you name a launcher to CREATE one, never to ask
# about one or to destroy one. `status` reports every launcher, so "is the
# prune-daemon running?" is answerable without remembering what you installed
# six months ago; `uninstall` sweeps them all, so a launcher can never be left
# armed because detection would now answer differently.
#
# ── WHAT A LAUNCHER MAY TOUCH ─────────────────────────────────────────────────
# ONLY FILES IT NAMED, AND ONLY UNITS IT CREATED. The launchd backend owns one
# plist; the systemd backend owns one `.service` and one `.timer`, both named
# after us, both under `~/.config/systemd/user/`. Neither reads or writes
# `user.conf`, `system.conf`, `DefaultTimerAccuracySec=`, or any unit it did not
# create, and `uninstall` leaves nothing behind. Same contract on both sides,
# and the same spirit as the line in ../../mod.nu about nothing of ours living
# in anyone else's config directory: a unit we own and can fully remove is ours;
# another tool's config file is not.
#
# The exports are `install-job` / `uninstall-job` / `status-of-job` /
# `prune-command` rather than the obvious install / uninstall / status /
# command, because `cli/prune-daemon.nu` publishes those as `prune-daemon
# install` and friends — and a command calling the name it is defining calls
# itself. Third time that rule has bitten (plan.md §10).

use launchd.nu
use systemd.nu

const SELF = path self

def module-root []: nothing -> string { $SELF | path dirname | path dirname | path dirname }

export def log-path []: nothing -> string {
    let base = $env.XDG_STATE_HOME? | default ($nu.home-dir | path join ".local" "state")
    $base | path join "agent-notify" "prune-daemon.log"
}

# The tick itself is just `displays refresh`: prune what is provably gone, then
# repaint whatever is left. Nothing here that a human could not type — and it is
# the same list of arguments whichever launcher ends up running it.
export def prune-command []: nothing -> list<string> {
    [ $nu.current-exe "-n" "--no-std-lib" "-c" $"use (module-root); agent-notify displays refresh" ]
}

# ── the launchers ─────────────────────────────────────────────────────────────
# Written by hand, like `core/dispatch.nu`'s integration-registry and for the
# same reason: nushell has no first-class modules, so a name cannot be turned
# into a module at runtime. A third launcher is one file plus one entry here.
export def launcher-registry []: nothing -> record {
    { launchd: {info: $launchd.INFO
                available: {|| launchd available }
                unit-files: {|tick, log, interval| launchd unit-files $tick $log $interval }
                register: {|| launchd register }
                unregister: {|| launchd unregister }
                status: {|| launchd status }}
      systemd: {info: $systemd.INFO
                available: {|| systemd available }
                unit-files: {|tick, log, interval| systemd unit-files $tick $log $interval }
                register: {|| systemd register }
                unregister: {|| systemd unregister }
                status: {|| systemd status }} }
}

export def launcher-registry-names []: nothing -> list<string> { launcher-registry | columns }

# A name the user typed → the launcher, or an error that lists the ones there
# are. Every command that takes a launcher goes through here first.
def resolve [launcher: string]: nothing -> record {
    let known = launcher-registry
    let entry = $known | get -o $launcher
    if $entry == null {
        error make --unspanned {msg: $"agent-notify: no launcher named '($launcher)' \(try: ($known | columns | str join ', '))"}
    }
    $entry
}

# What this launcher would write, without writing it. The pure half of the
# contract, exposed: it is how the systemd files are developed and asserted from
# a Mac, and how anyone can read what `install` is about to do.
export def unit-files [launcher: string, interval: int]: nothing -> table {
    do (resolve $launcher).unit-files (prune-command) (log-path) $interval
}

# The paths a launcher owns, for the two callers that want to delete them or ask
# whether they exist. No path has the interval in it, so any value will do — the
# 0 is there to say this is not a question about the contents.
def unit-paths [entry: record]: nothing -> list<string> {
    do $entry.unit-files (prune-command) (log-path) 0 | get path
}

# ── install ───────────────────────────────────────────────────────────────────
# Validate, then refuse the two cases that would be quietly wrong, then write and
# load. The order matters: nothing touches the disk until both refusals have had
# their say.
export def install-job [launcher: string, interval: int]: nothing -> record {
    let entry = resolve $launcher

    let can = do $entry.available
    if not $can.ok {
        error make --unspanned {msg: $"agent-notify: ($launcher) cannot run here — ($can.why)"}
    }

    # Two launchers ticking is harmless — a sweep and a repaint are both
    # idempotent — but it is confusing, and it is never what anyone meant.
    let armed = status-of-job | where {|r| ($r.launcher != $launcher) and $r.loaded }
    if ($armed | is-not-empty) {
        let other = $armed | get 0.launcher
        error make --unspanned {msg: $"agent-notify: ($other) is already running the prune-daemon — `agent-notify prune-daemon uninstall` first"}
    }

    let files = unit-files $launcher $interval
    mkdir (log-path | path dirname)
    for f in $files {
        mkdir ($f.path | path dirname)
        $f.text | save --force $f.path
    }

    let r = do $entry.register
    { launcher: $launcher
      interval: $interval
      files: ($files | get path)
      loaded: $r.ok
      why: $r.why }
}

# ── uninstall ─────────────────────────────────────────────────────────────────
# EVERY launcher, not the one you name — see the asymmetry above. Unload where
# the launcher can answer; delete the files always, because a unit file that
# arrived with someone's dotfiles is inert but should not be immortal.
export def uninstall-job []: nothing -> table {
    launcher-registry | transpose name entry | each {|l|
        let can = do $l.entry.available
        let unloaded = if $can.ok { (do $l.entry.unregister).ok } else { false }
        let present = unit-paths $l.entry | where {|f| $f | path exists }
        for f in $present { rm --force $f }
        {launcher: $l.name, unloaded: $unloaded, removed: ($present | length), files: $present}
    }
}

# ── status ────────────────────────────────────────────────────────────────────
# One row per launcher, whatever the machine is. A launcher that cannot run here
# still reports whether its files are lying around, which is the only way the
# dotfiles case is ever visible.
export def status-of-job []: nothing -> table {
    let log = log-path
    launcher-registry | transpose name entry | each {|l|
        let can = do $l.entry.available
        let s = if $can.ok {
            do $l.entry.status
        } else {
            {installed: (unit-paths $l.entry | any {|f| $f | path exists })
             loaded: false, running_now: false, last_exit: "", interval: 0}
        }
        {launcher: $l.name
         available: $can.ok
         why: $can.why
         installed: $s.installed
         loaded: $s.loaded
         running_now: $s.running_now
         last_exit: $s.last_exit
         interval: $s.interval
         log: $log}
    }
}
