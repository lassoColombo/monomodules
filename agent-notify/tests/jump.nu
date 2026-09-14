# What ZELLIJ is asked, when something wants to focus one of its panes.
#
# HALF A SUITE, because step 11 split the command from the integration (D74).
# Which agent you meant, and which integration has it, is `tests/jump-command.nu`
# — this file is one container's answer and nothing else. `find-session` appears
# only to turn a name into the record `jump argv` now takes.
#
# NOT ONE JUMP HAPPENS HERE, and that is the point of the file's shape. The
# cross-session branch moves a real screen to a real other session, which a test
# suite may not do — so `argv` is the whole decision as DATA and `main` is four
# lines that run it, exactly as `commands`/`push-items` split the display.
#
# One real zellij session IS created, detached and named after this suite,
# because the switch branch refuses to run against a session that does not exist
# (zellij would CREATE it) and that refusal is the thing worth proving.

use ../integrations/zellij/jump.nu
use ../core/find-session.nu
use ../core/session-store.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-jump")
const PROBE = "agent-notify-tests-jump"

def probe-session [action: string] {
    let z = which "zellij" | get -o 0.path | default "zellij"
    if $action == "up" {
        ^$z attach -b $PROBE | complete | ignore
    } else {
        ^$z delete-session $PROBE --force | complete | ignore
    }
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # A config that does not exist: nothing here may reach a real display.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    session-store patch "1111aaaa-0000" {agent: "claude", state: "working", name: "alpha"
                                 zellij: {session: "home", pane_id: "7"}}
    session-store patch "2222bbbb-0000" {agent: "claude", state: "awaiting", name: "beta"
                                 zellij: {session: "elsewhere", pane_id: "terminal_9"}}
    session-store patch "2222cccc-0000" {agent: "claude", state: "idle", name: "gamma"}

    # ── what zellij is asked ──────────────────────────────────────────────────
    # Same session: focus the pane, and nothing else. No `list-sessions` is run
    # on this path — a session that is gone answers for itself.
    $env.ZELLIJ_SESSION_NAME = "home"
    let same = jump argv (find-session "alpha")
    let b = [
        (check "a jump is a LIST of commands, even when it is one"
               ($same | length) 1)
        (check "in the same session, the pane is simply focused"
               ($same.0 | skip 1) ["--session" "home" "action" "focus-pane-id" "terminal_7"])
        (check "an ABSOLUTE program, because a daemon's PATH is not a shell's"
               ($same.0 | first | str starts-with "/") true)
    ]

    # Outside zellij altogether there is no client to move, so the best that can
    # be done is to tell the target session to move whatever client it has.
    hide-env ZELLIJ_SESSION_NAME
    let c = [
        (check "from outside zellij, the target session is asked directly"
               (jump argv (find-session "alpha") | get 0 | skip 1)
               ["--session" "home" "action" "focus-pane-id" "terminal_7"])
    ]

    # ── the switch, which is where the danger is ──────────────────────────────
    # `switch-session` CREATES a session it cannot find, so a record naming one
    # that has been killed must be refused rather than obeyed.
    $env.ZELLIJ_SESSION_NAME = "home"
    let d = [
        (check-err "a switch to a session that is gone is refused, not obeyed"
                   "has no session called 'elsewhere'" {|| jump argv (find-session "beta") })
        (check-err "…and says which agent claimed it" "'beta'"
                   {|| jump argv (find-session "beta") })
    ]

    # And against one that really is there, the switch is spelled out — note the
    # pane id, which `switch-session` will only take in its long form.
    probe-session "up"
    session-store patch "2222bbbb-0000" {zellij: {session: $PROBE}}
    let live = jump argv (find-session "beta")
    probe-session "down"
    let e = [
        (check "a live session is switched to, from the one asking"
               ($live.0 | skip 1)
               ["--session" "home" "action" "switch-session" $PROBE "--pane-id" "terminal_9"])
        (check "…and a pane id already in its long form is left alone"
               ($live.0 | last) "terminal_9")
    ]

    # ── the window, which only a caller from outside climbs to ────────────────
    # Two levels: the terminal's WINDOW, then the SESSION inside it. Inside
    # zellij by any route the window is already in front, so the rung is skipped
    # — and with nothing configured it does not exist at all, which is the
    # default and must stay byte-for-byte what it was (D72, D73).
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "windowed.yaml")
    "zellij: {commands: {focus_terminal_window: [/bin/echo, up, Ghostty]}}\n"
        | save --force $env.AGENT_NOTIFY_CONFIG

    hide-env ZELLIJ_SESSION_NAME
    let outside = jump argv (find-session "alpha")
    $env.ZELLIJ_SESSION_NAME = "home"
    let inside = jump argv (find-session "alpha")

    let g = [
        (check "from outside the terminal, the window is focused FIRST"
               ($outside | length) 2)
        (check "…with exactly the argv the user wrote"
               ($outside | first) ["/bin/echo" "up" "Ghostty"])
        (check "…and the pane after it, unchanged"
               ($outside | last | skip 1)
               ["--session" "home" "action" "focus-pane-id" "terminal_7"])
        (check "from inside zellij there is no window to climb to"
               ($inside | length) 1)
        (check-err "a setting that is not a list is a loud error, not a guess"
                   "must be a list of arguments"
                   {|| "zellij: {commands: {focus_terminal_window: nope}}\n"
                         | save --force $env.AGENT_NOTIFY_CONFIG
                       jump argv (find-session "alpha") })
        (check-err "…and a program that is not on PATH says why that matters here"
                   "not on PATH"
                   {|| "zellij: {commands: {focus_terminal_window: [definitely-not-a-program]}}\n"
                         | save --force $env.AGENT_NOTIFY_CONFIG
                       jump argv (find-session "alpha") })
    ]
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    # ── agents there is nowhere to jump to ────────────────────────────────────
    let f = [
        (check-err "an agent that was never seen in a pane is a clear no, not a crash"
                   "is not in a zellij pane" {|| jump argv (find-session "gamma") })
        (check-err "…named, so you know which one" "'gamma'"
                   {|| jump argv (find-session "gamma") })
    ]

    hide-env ZELLIJ_SESSION_NAME
    let all = ($b ++ $c ++ $d ++ $e ++ $f ++ $g)
    summarise $all --title "jump"
}
