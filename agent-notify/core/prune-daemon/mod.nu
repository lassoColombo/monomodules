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
# and each is the same five questions:
#
#   INFO             what it is, for `agent-notify prune-daemon status`
#   available        CAN this launcher run here? A PROBE, not a guess — the
#                    binary and, for systemd, a user manager that actually
#                    answers. Returns {ok, why}, and `why` is shown verbatim.
#   unit-files       PURE: (tick, log, interval) → the files to write, as
#                    {path, text}.
#   load-commands    PURE: the lines that load those files. `unload-commands` is
#                    its undo.
#   status           installed / loaded / last exit / the interval read back OUT
#                    of the unit file, because the file is the truth and not
#                    what someone typed once.
#
# ── AND NOTHING HERE IS APPLIED (D20) ─────────────────────────────────────────
# THE ONLY WRITER IS YOU. There is no `install`, and so there is nothing to
# `uninstall`: `help-setup` prints the files and the commands, the same as the
# hook wiring for an agent and the one line for a `sketchybarrc`. Four foreign
# configs in four formats now, and a LaunchAgent and a systemd unit are the most
# privileged of them — a thing that runs on a timer forever whether or not you
# remember agreeing to it.
#
# Which is why the launcher contract has no side effect left in it at all.
# `load-commands` BUILDS the lines rather than running them, the same rule as
# zellij's `commands` and the bar's `message` (integrations/mod.nu, rule 3), and
# the whole of this file that touches the world is `available` and `status` —
# both read-only, both answering questions somebody asked.
#
# ── NOTHING AUTODETECTS EITHER ────────────────────────────────────────────────
# `help-setup` takes the launcher as a REQUIRED argument (D67). The machine is
# not asked. Autodetection would be right ~always and invisible when wrong — and
# wrong looks exactly like "dead agents linger", with nothing in any log. So the
# user names it and the completer offers the two with a description each.
#
# But `available` is NOT a veto here, because printing is harmless: asking for
# the systemd files ON A MAC is the useful case, and it is how they are written
# and read. It puts a line at the top instead.
#
# `status` still answers for EVERY launcher, so "is the prune-daemon running?"
# never depends on remembering which one you set up.
#
# ── WHAT A LAUNCHER MAY TOUCH ─────────────────────────────────────────────────
# ONLY FILES IT NAMED, AND ONLY UNITS IT CREATED. The launchd launcher owns one
# plist; the systemd launcher owns one `.service` and one `.timer`, both named
# after us, both under `~/.config/systemd/user/`. Neither reads or writes
# `user.conf`, `system.conf`, `DefaultTimerAccuracySec=`, or any unit it did not
# create — and the teardown `help-setup` prints leaves nothing behind. Same
# spirit as the line in ../../mod.nu about nothing of ours living in anyone
# else's config directory: a unit we own and can fully remove is ours; another
# tool's config file is not.
#
# The exports are `setup-help` / `status-of-job` / `prune-command` rather than
# the obvious help-setup / status / command, because `cli/prune-daemon.nu`
# publishes those as `prune-daemon status` and friends — and a command calling
# the name it is defining calls itself. FOURTH time that rule has bitten — this
# one on `help-setup`, in the file that documents it (plan.md §10).

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
                load-commands: {|| launchd load-commands }
                unload-commands: {|| launchd unload-commands }
                status: {|| launchd status }}
      systemd: {info: $systemd.INFO
                available: {|| systemd available }
                unit-files: {|tick, log, interval| systemd unit-files $tick $log $interval }
                load-commands: {|| systemd load-commands }
                unload-commands: {|| systemd unload-commands }
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

# What this launcher would have you write. PURE — it is how the systemd files
# are developed and asserted from a Mac, and what `help-setup` lays out.
export def unit-files [launcher: string, interval: int]: nothing -> table {
    do (resolve $launcher).unit-files (prune-command) (log-path) $interval
}

# The paths a launcher owns, for the one caller that only wants to know whether
# they exist. No path has the interval in it, so any value will do — the 0 is
# there to say this is not a question about the contents.
def unit-paths [entry: record]: nothing -> list<string> {
    do $entry.unit-files (prune-command) (log-path) 0 | get path
}

# ── help-setup ────────────────────────────────────────────────────────────────
# The files, then the commands, then the way back out. Printed, never applied.
export def setup-help [launcher: string, interval: int]: nothing -> string {
    let entry = resolve $launcher
    let can = do $entry.available
    let files = unit-files $launcher $interval
    let log = log-path

    let preface = if $can.ok { [] } else {
        [ $"NOTE: this machine cannot run ($launcher) — ($can.why)."
          "      The files below are still right for one that can."
          "" ]
    }

    let write = $files | each {|f|
        [ $"Write ($f.path):"
          ""
          ($f.text | lines | each {|l| $"    ($l)" } | str join "\n")
          "" ]
    } | flatten

    ([ ...$preface
       $"The prune-daemon looks every ($interval)s under ($entry.info.title)."
       "Nothing below is applied — run it yourself, or do not."
       ""
       "Make the log directory, or a failing tick has nowhere to say so:"
       ""
       $"    mkdir -p ($log | path dirname)"
       ""
       ...$write
       "Load it:"
       ""
       ...(do $entry.load-commands | each {|c| $"    ($c)" })
       ""
       "`agent-notify prune-daemon status` says whether it took."
       ""
       "To undo, in this order — deleting the files does not unload them, and"
       "the unload may clean up things that are not files:"
       ""
       ...(do $entry.unload-commands | each {|c| $"    ($c)" })
       ...($files | each {|f| $"    rm ($f.path)" }) ] | str join "\n")
}

# ── status ────────────────────────────────────────────────────────────────────
# One row per launcher, whatever the machine is. A launcher that cannot run here
# still reports whether its files are lying around, which is the only way a unit
# that arrived with someone's dotfiles is ever visible.
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
