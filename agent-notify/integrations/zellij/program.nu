# Which zellij — and nothing else.
#
# A file of its own because it is the one thing BOTH halves of this integration
# need: the same program renames a pane and focuses one. That is exactly what the
# config file says by putting `binary` ABOVE `surface:` and `commands:`
# (plan.md D47), so the code mirrors the file rather than contradicting it.
#
# Imported by `mod.nu` (push) and by `jump.nu` (pull). Those are two import paths,
# so this is parsed twice — but only ever on a COLD one: the hook reaches `mod.nu`
# and stops, and nothing a human types is on a budget. Duplicating it instead
# would put the same 15 lines in two places and let their error messages drift.

# An ABSOLUTE path, because a hook's PATH is not your shell's PATH and a LAUNCHD
# JOB's is smaller still — /usr/bin:/bin and nothing else, which is how the bar's
# clock was found silently painting nothing. Resolved once, where settings are
# built, so a missing program is a loud configuration error rather than a command
# that reports success and does nothing.
#
# No `-> string` signature: a def annotated that way cannot END in `error make`
# (plan.md §10).
export def resolve [given: string] {
    if ($given | is-not-empty) {
        if not ($given | path exists) {
            error make --unspanned {msg: $"zellij: no program at '($given)'"}
        }
        return $given
    }
    let found = which "zellij" | get -o 0.path | default ""
    if ($found | is-not-empty) { return $found }
    for d in ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin"] {
        let p = $d | path join "zellij"
        if ($p | path exists) { return $p }
    }
    error make --unspanned {msg: ("zellij: not found. Set `zellij.binary: <path>` in the config "
        + "file if it lives somewhere unusual.")}
}
