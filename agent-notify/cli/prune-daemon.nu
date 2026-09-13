# `agent-notify prune-daemon …` — the periodic look, and whether it is
# happening.
#
# See core/prune-daemon.nu for why this exists at all: a dead agent fires no
# hook, so something has to go and check. It is the same prune the session-store
# already has, on a timer that belongs to nobody in particular — not to the bar,
# which is optional.

use ../core/prune-daemon.nu

@search-terms agent notify prune-daemon timer periodic prune launchd install
@example "start checking every 30s" { agent-notify prune-daemon install }
export def "prune-daemon install" [--interval: int = 30]: nothing -> nothing {
    if $interval < 10 {
        error make --unspanned {msg: "agent-notify: an interval under 10s is a busy loop, not a prune-daemon"}
    }
    let r = prune-daemon install-job $interval
    if $r.loaded {
        print $"(ansi green)running(ansi reset) every ($r.interval)s — ($r.path)"
    } else {
        print $"(ansi red)failed to load(ansi reset) ($r.path)"
        error make --unspanned {msg: $"agent-notify: launchctl refused it: ($r.why)"}
    }
}

@search-terms agent notify prune-daemon status running loaded launchd
@example "is the periodic check alive?" { agent-notify prune-daemon status }
export def "prune-daemon status" []: nothing -> record { prune-daemon status-of-job }

@search-terms agent notify prune-daemon uninstall remove stop launchd
export def "prune-daemon uninstall" []: nothing -> record { prune-daemon uninstall-job }

# What the tick would run, for anyone who wants to see it or run it by hand.
@search-terms agent notify prune-daemon command tick what
export def "prune-daemon command" []: nothing -> string { prune-daemon prune-command | str join " " }
