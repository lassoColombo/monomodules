# `agent-notify2 config …` — where the settings live, what they say, and what is
# wrong with them.
#
# Cold: no entry point comes near this file. The hot path reads the same config
# through `core/config.nu`, which never throws; everything loud lives here, where
# a human is present to read it.
#
# The commands are multi-word on purpose. `config` is a BUILTIN, so a def by that
# name would shadow it for every module that imports this one — multi-word
# subcommands are exempt from that rule (plan.md §10).

use ../core/config.nu
use ../core/dispatch.nu

@search-terms agent notify config settings yaml where file path
@example "where does it look?" { agent-notify2 config path }
export def "config path" []: nothing -> string { config file }

# The resolved settings and where they came from. `surfaces` is pulled out because
# it is the one question that gets asked: what is actually turned on?
@search-terms agent notify config show settings resolved
@example "what is configured?" { agent-notify2 config show }
export def "config show" []: nothing -> record {
    let f = config file
    { path: $f
      exists: ($f | path exists)
      surfaces: (config enabled)
      settings: (config load) }
}

# Strict, and loud. Errors rather than returning a table, because this is the one
# command whose whole purpose is to fail when something is wrong: a hook that
# silently stops painting is exactly the outcome this exists to explain.
#
# No `-> nothing` signature: a def annotated that way cannot END in `error make`,
# because `error` is not `nothing`. Nor can a comment sit between an attribute and
# its definition — both §10.
@search-terms agent notify config check validate verify lint
@example "is my config sane?" { agent-notify2 config check }
export def "config check" [] {
    let f = config file
    let found = config problems (dispatch known)

    if ($found | is-empty) {
        if ($f | path exists) {
            print $"(ansi green)ok(ansi reset) ($f)"
        } else {
            print $"(ansi dark_gray)no config file at ($f) — no surfaces are on(ansi reset)"
        }
        return
    }

    print $"(ansi red)($f)(ansi reset)"
    print ($found | each {|p| $"  ($p)" } | str join "\n")
    error make --unspanned {msg: $"agent-notify: ($found | length) problem\(s\) in the config file"}
}
