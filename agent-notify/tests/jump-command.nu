# `agent-notify jump <who>` — which agent you meant, and which integration has
# it.
#
# THE OTHER HALF OF THE OLD `tests/jump.nu`, split when the command stopped
# being zellij's (D75). What is asserted here names no tool: a name or a prefix
# becomes a record (`core/find-session.nu`), a record finds the containers that
# claim it (`integrations/session-containers.nu`), and each is asked in turn
# (`cli/jump.nu`). What zellij does with the asking is `tests/jump.nu`.
#
# AND THE WALK ITSELF, on fakes. A session is at a PATH through containers
# (D77), so the composition needs two of them to mean anything — `tests/fake.nu`
# ships an inner and an outer, and the outer is the awkward shape the real one
# has: it claims optimistically and only finds out at argv time whether it can
# reach anything.
#
# NOT ONE JUMP HAPPENS HERE either — every check goes through `--dry-run`, which
# is the whole reason the contract has a data half in front of `focus-session`.

use ../cli/jump.nu
use ../core/session-store.nu
use ../integrations/session-containers.nu
use fake.nu
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
    # those containers would run.
    let alpha = session-store read "1111aaaa-0000"
    let b = [
        (check "the command hands back exactly what the registry would run"
               (jump "alpha" --dry-run) (session-containers focus-session-argv $alpha))
        (check "…which is a LIST of commands, even when the path is one long"
               (jump "alpha" --dry-run | length) 1)
        (check "zellij is the only container shipped so far"
               (session-containers containers-of $alpha | get info.name) ["zellij"])
    ]

    # ── and an agent nothing contains ─────────────────────────────────────────
    # The ordinary case for an agent that has never been seen in a pane: a bare
    # terminal, or a script. A sentence, not a crash, and not a zellij-shaped
    # error about panes for an agent that was never near zellij.
    let c = [
        (check "an agent no integration claims has an empty path"
               (session-containers containers-of (session-store read "2222cccc-0000")) [])
        (check-err "…and the command says so without naming a tool"
                   "is not inside anything that can be jumped to"
                   {|| jump "gamma" --dry-run })
        (check-err "…named, so you know which one" "'gamma'" {|| jump "gamma" --dry-run })
    ]

    # ── THE WALK: a session is at a PATH, not in a place (D77) ────────────────
    # Two fake containers, outermost first, and the order of the table is the
    # nesting order (D78) — nothing derives it, nothing configures it.
    let chain = fake session-container-chain
    let reachable = {id: "d1", fake: {where: "box/one", outer: "desk-3"}}
    let stranded = {id: "d2", fake: {where: "box/two"}}
    let unclaimed = {id: "d3"}
    let d = [
        (check "every container that claims a session is returned, not just the first"
               (session-containers containers-of $reachable --table $chain | get info.name)
               ["fake-outer" "fake"])
        (check "…OUTERMOST FIRST, which is the order the table is written in"
               (session-containers containers-of $reachable --table $chain | get -o 0.info.name)
               "fake-outer")
        (check "the path's commands are concatenated, outside in"
               (session-containers focus-session-argv $reachable --table $chain)
               [["echo" "outer" "desk-3"] ["echo" "fake" "box/one"]])
        # The outer container CLAIMS whatever it can name, and only finds out at
        # argv time whether it can actually reach it — because only the world
        # knows, and `owns-session` may not ask the world (the picker calls it
        # for every record every two seconds).
        (check "a container that claims but cannot reach drops out, rather than failing the path"
               (session-containers focus-session-argv $stranded --table $chain)
               [["echo" "fake" "box/two"]])
        (check "…and it still counts as a claimant, because it is still where the session lives"
               (session-containers containers-of $stranded --table $chain | length) 2)
        (check "a session nothing claims has no path and no commands"
               [(session-containers containers-of $unclaimed --table $chain)
                (session-containers focus-session-argv $unclaimed --table $chain)]
               [[] []])
    ]

    # ── the label is a PATH too ───────────────────────────────────────────────
    # Each container's own label, outside in, joined — and one with nothing
    # worth a column says "" and drops out rather than padding it.
    let e = [
        (check "a chain's label is the labels that have something to say"
               (session-containers location-label $reachable --table $chain) "box/one")
        (check "…and a session nothing claims has no label at all"
               (session-containers location-label $unclaimed --table $chain) "")
        # alpha's record knows its session but not its tab, which is what a
        # pane looks like before `discover-own-location` has paid for a
        # `list-panes` — so the label is the session and nothing else.
        (check "a one-container path is unchanged by any of this"
               (session-containers location-label $alpha) "home")
    ]

    hide-env ZELLIJ_SESSION_NAME
    summarise ($a ++ $b ++ $c ++ $d ++ $e) --title "jump-command"
}
