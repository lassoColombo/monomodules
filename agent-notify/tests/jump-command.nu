# `agent-notify jump <who>` — which agent you meant, and which integration has
# it.
#
# THE OTHER HALF OF THE OLD `tests/jump.nu`, split when the command stopped
# being zellij's (D75). What is asserted here names no tool: a name or a prefix
# becomes a record (`core/find-session.nu`), a record finds the container that
# claims it (`integrations/session-containers.nu`), and the container is asked
# (`cli/jump.nu`). What zellij does with the asking is `tests/jump.nu`.
#
# NOT ONE JUMP HAPPENS HERE either — every check goes through `--dry-run`, which
# is the whole reason the contract has a data half in front of `focus-session`.

use ../cli/jump.nu
use ../core/session-store.nu
use ../integrations/session-containers.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-jump-command")

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

    # ── which agent you meant ─────────────────────────────────────────────────
    # An id is a uuid. Nobody types one, so neither should this command insist.
    $env.ZELLIJ_SESSION_NAME = "home"
    let a = [
        (check "an exact id finds it" (jump "1111aaaa-0000" --dry-run | get 0.5) "terminal_7")
        (check "so does a unique prefix" (jump "1111" --dry-run | get 0.5) "terminal_7")
        (check "…and so does the name the agent gave itself"
               (jump "alpha" --dry-run | get 0.5) "terminal_7")
        (check-err "a prefix matching nothing says so, and says where to look"
                   "no agent called 'zzz'" {|| jump "zzz" --dry-run })
        (check-err "…and an ambiguous one lists the candidates rather than guessing"
                   "could be any of" {|| jump "2222" --dry-run })
        (check-err "…naming them" "2222bbbb-0000" {|| jump "2222" --dry-run })
    ]

    # ── which integration has it ──────────────────────────────────────────────
    # The seam, and the reason this file names no tool: the command asks the
    # registry, the registry asks the record, and what comes back is whatever
    # that container would run.
    let container = session-containers container-of (session-store read "1111aaaa-0000")
    let b = [
        (check "the command hands back exactly what the container would run"
               (jump "alpha" --dry-run)
               (do $container.focus-session-argv (session-store read "1111aaaa-0000")))
        (check "…which is a LIST of commands, even when it is one"
               (jump "alpha" --dry-run | length) 1)
    ]

    # ── and an agent nothing contains ─────────────────────────────────────────
    # The ordinary case for an agent that has never been seen in a pane: a bare
    # terminal, or a script. A sentence, not a crash, and not a zellij-shaped
    # error about panes for an agent that was never near zellij.
    let c = [
        (check "an agent no integration claims has no container"
               (session-containers container-of (session-store read "2222cccc-0000")) null)
        (check-err "…and the command says so without naming a tool"
                   "is not inside anything that can be jumped to"
                   {|| jump "gamma" --dry-run })
        (check-err "…named, so you know which one" "'gamma'" {|| jump "gamma" --dry-run })
    ]

    hide-env ZELLIJ_SESSION_NAME
    summarise ($a ++ $b ++ $c) --title "jump-command"
}
