# Step 6 — `agent-notify jump`: which agent you meant, and what zellij is asked.
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

    session-store patch "1111aaaa-0000" {client: "claude", state: "working", name: "alpha"
                                 zellij: {session: "home", pane_id: "7"}}
    session-store patch "2222bbbb-0000" {client: "claude", state: "awaiting", name: "beta"
                                 zellij: {session: "elsewhere", pane_id: "terminal_9"}}
    session-store patch "2222cccc-0000" {client: "claude", state: "idle", name: "gamma"}

    # ── which agent you meant ─────────────────────────────────────────────────
    # An id is a uuid. Nobody types one, so neither should this command insist.
    let a = [
        (check "an exact id finds it" (jump find "1111aaaa-0000" | get name) "alpha")
        (check "so does a unique prefix" (jump find "1111" | get name) "alpha")
        (check "…and so does the name the agent gave itself"
               (jump find "beta" | get id) "2222bbbb-0000")
        (check "a name beats a prefix that also matches something else"
               (jump find "gamma" | get id) "2222cccc-0000")
        (check-err "a prefix matching nothing says so, and says where to look"
                   "no agent called 'zzz'" {|| jump find "zzz" })
        (check-err "…and an ambiguous one lists the candidates rather than guessing"
                   "could be any of" {|| jump find "2222" })
        (check-err "…naming them" "2222bbbb-0000" {|| jump find "2222" })
    ]

    # ── what zellij is asked ──────────────────────────────────────────────────
    # Same session: focus the pane, and nothing else. No `list-sessions` is run
    # on this path — a session that is gone answers for itself.
    $env.ZELLIJ_SESSION_NAME = "home"
    let same = jump argv "alpha"
    let b = [
        (check "in the same session, the pane is simply focused"
               ($same | skip 1) ["--session" "home" "action" "focus-pane-id" "terminal_7"])
        (check "an ABSOLUTE program, because a daemon's PATH is not a shell's"
               ($same | first | str starts-with "/") true)
    ]

    # Outside zellij altogether there is no client to move, so the best that can
    # be done is to tell the target session to move whatever client it has.
    hide-env ZELLIJ_SESSION_NAME
    let c = [
        (check "from outside zellij, the target session is asked directly"
               (jump argv "alpha" | skip 1)
               ["--session" "home" "action" "focus-pane-id" "terminal_7"])
    ]

    # ── the switch, which is where the danger is ──────────────────────────────
    # `switch-session` CREATES a session it cannot find, so a record naming one
    # that has been killed must be refused rather than obeyed.
    $env.ZELLIJ_SESSION_NAME = "home"
    let d = [
        (check-err "a switch to a session that is gone is refused, not obeyed"
                   "has no session called 'elsewhere'" {|| jump argv "beta" })
        (check-err "…and says which agent claimed it" "'beta'" {|| jump argv "beta" })
    ]

    # And against one that really is there, the switch is spelled out — note the
    # pane id, which `switch-session` will only take in its long form.
    probe-session "up"
    session-store patch "2222bbbb-0000" {zellij: {session: $PROBE}}
    let live = jump argv "beta"
    probe-session "down"
    let e = [
        (check "a live session is switched to, from the one asking"
               ($live | skip 1)
               ["--session" "home" "action" "switch-session" $PROBE "--pane-id" "terminal_9"])
        (check "…and a pane id already in its long form is left alone"
               ($live | last) "terminal_9")
    ]

    # ── agents there is nowhere to jump to ────────────────────────────────────
    let f = [
        (check-err "an agent that was never seen in a pane is a clear no, not a crash"
                   "is not in a zellij pane" {|| jump argv "gamma" })
        (check-err "…named, so you know which one" "'gamma'" {|| jump argv "gamma" })
    ]

    hide-env ZELLIJ_SESSION_NAME
    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f)
    summarise $all --title "jump"
}
