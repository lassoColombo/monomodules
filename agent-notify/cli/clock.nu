# `agent-notify clock …` — the periodic look, and whether it is happening.
#
# See core/clock.nu for why this exists at all: a dead agent fires no hook, so
# something has to go and check. It is the same prune the store already has, on a
# timer that belongs to nobody in particular — not to the bar, which is optional.

use ../core/clock.nu

@search-terms agent notify clock timer periodic prune launchd install
@example "start checking every 30s" { agent-notify clock install }
export def "clock install" [--interval: int = 30]: nothing -> nothing {
    if $interval < 10 {
        error make --unspanned {msg: "agent-notify: an interval under 10s is a busy loop, not a clock"}
    }
    let r = clock arm $interval
    if $r.loaded {
        print $"(ansi green)running(ansi reset) every ($r.interval)s — ($r.path)"
    } else {
        print $"(ansi red)failed to load(ansi reset) ($r.path)"
        error make --unspanned {msg: $"agent-notify: launchctl refused it: ($r.why)"}
    }
}

@search-terms agent notify clock status running loaded launchd
@example "is the periodic check alive?" { agent-notify clock status }
export def "clock status" []: nothing -> record { clock check }

@search-terms agent notify clock uninstall remove stop launchd
export def "clock uninstall" []: nothing -> record { clock disarm }

# What the tick would run, for anyone who wants to see it or run it by hand.
@search-terms agent notify clock command tick what
export def "clock command" []: nothing -> string { clock tick | str join " " }
