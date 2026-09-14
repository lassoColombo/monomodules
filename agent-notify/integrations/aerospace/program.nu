# Which aerospace — and whether there is one at all.
#
# THE ASYMMETRY WITH `zellij/program.nu`, and it is the whole reason this file
# differs: **a missing zellij is not a case, a missing aerospace is.**
#
# zellij's resolver raises when it cannot find the program, and that is correct
# there — a record only carries a `zellij` namespace because a zellij put it
# there, so being asked to focus a zellij pane on a machine with no zellij means
# something is badly wrong. Aerospace claims a session because of what the
# INNER container wrote (see `session-container.nu`), so it will claim on a
# machine that has never had a window manager installed. Raising there would
# make a jump fail on every such machine, and stop-at-the-first-failure means it
# would take the pane focus down with it.
#
# So: "" means NOT INSTALLED, and the container turns that into "I have nothing
# to do" — which the walk steps straight past. It is not the same answer as "I
# tried and could not" and it must not be spelled the same way.
use ../../core/config.nu

export def resolve []: nothing -> string {
    from-setting ((config settings-for (config load) "aerospace" "commands").binary? | default "")
}

# Split out so `commands-settings` can validate a value without going near the
# config file, which is what `agent-notify config check` needs.
export def from-setting [given: string]: nothing -> string {
    if ($given | is-not-empty) { return (if ($given | path exists) { $given } else { "" }) }
    let found = which "aerospace" | get -o 0.path | default ""
    if ($found | is-not-empty) { return $found }
    for d in ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin"] {
        let p = $d | path join "aerospace"
        if ($p | path exists) { return $p }
    }
    ""
}
