# aerospace as a session-container — the outermost rung of a path.
#
# NOT ONE WINDOW IS TOUCHED, and no aerospace has to be installed. The container
# splits the way every side effect in this module does (rule 3 of
# `integrations/mod.nu`): `window-id-for` is a PURE function of a window list
# and a title prefix, so the matching — which is the only thinking this file
# does — is asserted against hand-written windows.
#
# What is NOT asserted here is that aerospace behaves as described. That was
# PROBED, once, on a real machine, and written up in plan.md §11 and
# `bench/aerospace-windows.nu`. A suite that shells out to a window manager
# would be a suite that only runs on one desktop.

# `use <path> as <name>` does not exist; a `module` block re-exporting the file
# is the mechanism that does (§10, and the same two lines
# `integrations/session-containers.nu` uses to hold two of these at once).
module aerospace { export use ../integrations/aerospace/session-container.nu * }
use aerospace
use ../integrations/session-containers.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-aerospace")

# The shape `list-windows --all --format '%{window-id}|%{window-title}'` parses
# into. A real desktop: a browser, two terminals, and something with a name that
# is very nearly a session's.
def desktop []: nothing -> list<record> {
    [{id: "577", title: "untitled - asciinema.org — lasso"}
     {id: "39",  title: "home | snip"}
     {id: "5674", title: "work | build-the-thing"}
     {id: "88",  title: "homework - Notes"}]
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    mkdir $TMP
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    let in_zellij = {id: "a", zellij: {session: "home", pane_id: "7"}}
    let no_pane = {id: "b", zellij: {session: "work"}}
    let nowhere = {id: "c"}

    # ── what it claims ────────────────────────────────────────────────────────
    # `owns-session` may not run a program: the picker asks it for every record
    # every two seconds. So it claims anything it could LOOK for, and finds out
    # at jump time whether the window is really there.
    let a = [
        (check "a session whose window we could look for is claimed"
               (aerospace owns-session $in_zellij) true)
        (check "…even without a pane, because a window is not a pane"
               (aerospace owns-session $no_pane) true)
        (check "a session with nothing to look for is not claimed"
               (aerospace owns-session $nowhere) false)
        (check "it contributes no label — the session name beside it already says the place"
               (aerospace location-label $in_zellij) "")
    ]

    # ── the matching, which is the whole of the thinking ──────────────────────
    # zellij titles its window `<session> | <active tab>`. The separator is what
    # makes the match specific: `home` alone would also match `homework`.
    let b = [
        (check "the window titled for the session is found"
               (aerospace window-id-for (desktop) "home | ") "39")
        (check "…and a different session finds a different window"
               (aerospace window-id-for (desktop) "work | ") "5674")
        (check "A SESSION NAME THAT IS A PREFIX OF A WORD DOES NOT MATCH IT"
               (aerospace window-id-for (desktop) "homework | ") "")
        (check "…which is what the separator is for — without it, `homework` would match too"
               ((desktop) | where {|w| $w.title | str starts-with "home" } | get id) ["39" "88"])
        (check "no window for this session is an empty answer, not an error"
               (aerospace window-id-for (desktop) "elsewhere | ") "")
        (check "nothing to look for is an empty answer too"
               (aerospace window-id-for (desktop) "") "")
        (check "an empty desktop is an empty answer"
               (aerospace window-id-for [] "home | ") "")
        # Two terminal windows attached to ONE zellij session would both match.
        # Untested against a real desktop (§11) — arbitrary but STABLE beats a
        # coin toss, and beats refusing to move.
        (check "first match wins, and it is the first in aerospace's own order"
               (aerospace window-id-for [{id: "1", title: "home | a"} {id: "2", title: "home | b"}] "home | ")
               "1")
    ]

    # ── no aerospace installed is NOT a failure ───────────────────────────────
    # It is the case that must not break a jump: this container claims from what
    # the INNER one wrote, so it claims on machines that have never had a window
    # manager. A failure here would stop the walk and take the pane focus with
    # it, so "not installed" has to spell "nothing to do".
    "aerospace: {commands: {binary: /nope/aerospace}}\n" | save --force $env.AGENT_NOTIFY_CONFIG
    let c = [
        (check "a binary that is not there resolves to nothing, rather than raising"
               (aerospace focus-session-argv $in_zellij) [])
        (check "…so the walk steps straight past it, leaving the pane rung alone"
               (session-containers focus-session-argv $in_zellij | each {|c| $c | first | path basename })
               ["zellij"])
        (check "…and it still CLAIMS, because where the session lives has not changed"
               (session-containers containers-of $in_zellij | get info.name)
               ["aerospace" "zellij"])
    ]

    # ── and what a human is told about the same setting ───────────────────────
    # Loud here, quiet at jump time, and that asymmetry is deliberate: someone
    # asking "is my config right" wants to be told.
    let d = [
        (check-err "a binary that is not there is a loud error when a human asks"
                   "no program at" {|| aerospace commands-settings {binary: "/nope/aerospace"} })
        (check-err "a setting we do not have is a typo" "is not a command setting"
                   {|| aerospace commands-settings {binry: "x"} })
        (check "and an empty half is fine — the program is found on PATH"
               (aerospace commands-settings {} | columns) ["binary"])
    ]

    rm --recursive --force $TMP
    summarise ($a ++ $b ++ $c ++ $d) --title "aerospace"
}
