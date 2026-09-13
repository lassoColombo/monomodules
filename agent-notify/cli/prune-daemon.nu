# `agent-notify prune-daemon …` — the periodic look, and whether it is
# happening.
#
# See core/prune-daemon/mod.nu for why this exists at all: a dead agent fires no
# hook, so something has to go and check. It is the same sweep the session-store
# already has, on a timer that belongs to nobody in particular — not to the bar,
# which is optional.
#
# THE LAUNCHER IS NAMED, NOT DETECTED (D67), and only on `install`: you name one
# to CREATE it, never to ask about one or to destroy one. `status` reports every
# launcher and `uninstall` sweeps them all, so neither depends on remembering
# what was installed, or on detection answering the same way twice.

use ../core/prune-daemon

# The completer. It reads the registry rather than listing the names again, so a
# third launcher cannot appear in `install` and be missing from the menu — and
# the `description` column is what the menu shows beside each one, which is where
# the choice gets explained now that nothing autodetects it.
def launchers []: nothing -> table {
    prune-daemon launcher-registry
    | transpose name entry
    | each {|l| {value: $l.name, description: $l.entry.info.title} }
}

@search-terms agent notify prune-daemon install timer periodic launchd systemd
@example "look every 30s, under launchd" { agent-notify prune-daemon install launchd }
@example "…or under systemd, every minute" { agent-notify prune-daemon install systemd --interval 60 }
export def "prune-daemon install" [
    launcher: string@launchers   # launchd or systemd — see `agent-notify prune-daemon status`
    --interval: int = 30         # seconds between looks; both launchers honour it exactly
]: nothing -> nothing {
    if $interval < 10 {
        error make --unspanned {msg: "agent-notify: an interval under 10s is a busy loop, not a prune-daemon"}
    }
    let r = prune-daemon install-job $launcher $interval
    if not $r.loaded {
        print $"(ansi red)failed to load(ansi reset) ($r.files | str join ', ')"
        error make --unspanned {msg: $"agent-notify: ($launcher) refused it: ($r.why)"}
    }
    print $"(ansi green)running(ansi reset) under ($r.launcher), every ($r.interval)s"
    print ($r.files | each {|f| $"  ($f)" } | str join "\n")
}

@search-terms agent notify prune-daemon status running loaded launchd systemd
@example "is the periodic check alive?" { agent-notify prune-daemon status }
export def "prune-daemon status" []: nothing -> table { prune-daemon status-of-job }

# Every launcher, not the one you name. A launcher that cannot run here still has
# its files removed if they are lying about.
@search-terms agent notify prune-daemon uninstall remove stop launchd systemd
@example "stop looking, whichever launcher was doing it" { agent-notify prune-daemon uninstall }
export def "prune-daemon uninstall" []: nothing -> table { prune-daemon uninstall-job }

# What `install` would write, written nowhere. The pure half of a launcher,
# exposed — read it before you install, or read a systemd timer from a Mac.
@search-terms agent notify prune-daemon unit plist timer service preview dry-run
@example "what would the systemd timer say?" { agent-notify prune-daemon unit systemd }
export def "prune-daemon unit" [
    launcher: string@launchers   # launchd or systemd
    --interval: int = 30
]: nothing -> string {
    prune-daemon unit-files $launcher $interval
    | each {|f| $"(ansi cyan)# ($f.path)(ansi reset)\n($f.text)" }
    | str join "\n"
}

# What the tick would run, for anyone who wants to see it or run it by hand. The
# same list of arguments whichever launcher ends up running it.
@search-terms agent notify prune-daemon command tick what
export def "prune-daemon command" []: nothing -> string { prune-daemon prune-command | str join " " }
