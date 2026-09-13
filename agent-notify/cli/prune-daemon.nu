# `agent-notify prune-daemon …` — the periodic look, and whether it is
# happening.
#
# See core/prune-daemon/mod.nu for why this exists at all: a dead agent fires no
# hook, so something has to go and check. It is the same sweep the session-store
# already has, on a timer that belongs to nobody in particular — not to the bar,
# which is optional.
#
# TWO COMMANDS, AND NEITHER WRITES ANYTHING. `help-setup` prints the unit files
# and the commands that load them, the same as `agents help-setup` prints hooks
# and `displays help-setup` prints a sketchybarrc line (D20). `status` reads. A
# LaunchAgent and a systemd timer are the most privileged things this module
# knows how to describe, and describing is as far as it goes.
#
# THE LAUNCHER IS NAMED, NOT DETECTED (D67). `status` still answers for every
# launcher, so asking whether the prune-daemon is running never depends on
# remembering which one you set up.

use ../core/prune-daemon

# The completer. It reads the registry rather than listing the names again, so a
# third launcher cannot appear in `help-setup` and be missing from the menu —
# and the `description` column is what the menu shows beside each one, which is
# where the choice gets explained now that nothing autodetects it.
def launchers []: nothing -> table {
    prune-daemon launcher-registry
    | transpose name entry
    | each {|l| {value: $l.name, description: $l.entry.info.title} }
}

# Printed, never applied — including for a launcher this machine cannot run,
# because reading the systemd files from a Mac is the useful case.
@search-terms agent notify prune-daemon help-setup setup install launchd systemd plist timer
@example "set the prune-daemon up under launchd" { agent-notify prune-daemon help-setup launchd }
@example "…or under systemd, every minute" { agent-notify prune-daemon help-setup systemd --interval 60 }
export def "prune-daemon help-setup" [
    launcher: string@launchers   # launchd or systemd — see `agent-notify prune-daemon status`
    --interval: int = 30         # seconds between looks; both launchers honour it exactly
]: nothing -> string {
    if $interval < 10 {
        error make --unspanned {msg: "agent-notify: an interval under 10s is a busy loop, not a prune-daemon"}
    }
    prune-daemon setup-help $launcher $interval
}

@search-terms agent notify prune-daemon status running loaded launchd systemd
@example "is the periodic check alive?" { agent-notify prune-daemon status }
export def "prune-daemon status" []: nothing -> table { prune-daemon status-of-job }

# What the tick would run, for anyone who wants to see it or run it by hand. The
# same list of arguments whichever launcher ends up running it.
@search-terms agent notify prune-daemon command tick what
export def "prune-daemon command" []: nothing -> string { prune-daemon prune-command | str join " " }
