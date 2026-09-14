# `agent-notify browse [query]` — the fleet as a list, and land in the one you
# pick.
#
# IN `cli/`, NOT IN `integrations/zellij/`, and that placement is the point.
# v1's picker was a zellij program with a fuzzy finder bolted on; this one is a
# picker that asks whichever integration CONTAINS an agent where it lives and
# how to get there (`integrations/session-containers.nu`). Nothing in it is
# zellij's, so nothing in it belongs in zellij's directory — a tmux integration
# adds one file and one row in that table, and never touches this command.
#
# IT RUNS IN PLACE (D52). v1 re-launched itself inside a `zellij run --floating`
# pane and needed a `--here` flag to not do that. The floating pane belongs to
# your keybinding — `agent-notify browse help-setup` prints it — which is the
# same bargain as the one line in `sketchybarrc` and the eight in
# `settings.json`: we describe what to put in your config and never write it
# (D20).
#
# AND IT DOES NOT PRUNE (D53). A dead agent is the prune-daemon's business
# (core/prune-daemon/, every 30s). Pruning here too would be a second
# mechanism for one guarantee, and the worst it saves you from is a jump that
# says "no session called 'x'".

# A DIAMOND, KNOWINGLY, AND IT IS NOT FREE. `picker/rows.nu` reaches
# `session-containers` too — it needs the labels — so that cone is parsed by two
# import paths and therefore twice (§10). MEASURED: browse costs 37.8ms with it
# and 34.2ms without, so the diamond is **3.7ms**.
#
# Kept, because both consumers are RIGHT: a picker asks which container claims a
# record, and a jump asks that container to go there. Removing it means making
# one of them wrong — either the picker stops resolving its own labels, or this
# file walks the path itself and the stop-at-first-failure rule lives in two
# places. D29 is about the HOT cone, where 2.5ms was every tool call forever;
# this is 3.7ms on a picker a human opened and is waiting 37ms for anyway.
use ../core/session-store.nu
use ../integrations/session-containers.nu
use ../picker

const SELF = path self

# Pick an agent and go there. `query` prefills the filter, which leaves you in
# the list with a shorter list rather than staring at an error.
@search-terms agent notify browse pick picker choose list agents fleet preview
@example "choose an agent and land in its pane" { agent-notify browse }
@example "…starting from a filter" { agent-notify browse zz }
export def main [
    query?: string      # prefills the filter
] {
    if (session-store list | is-empty) {
        print $"(ansi dark_gray)no agents(ansi reset)"
        return
    }
    let picked = picker choose --query ($query | default "")
    if ($picked == null) { return }

    # Nothing claimed it, so there is nowhere to go — an agent that never
    # reported a pane. Worth a sentence rather than a silent return: you chose
    # it on purpose.
    if ($picked.containers | is-empty) {
        error make --unspanned {msg: $"agent-notify: '($picked.name)' is not in a pane — nothing to jump to"}
    }
    session-containers focus-session $picked.rec
}

# What to put in your zellij config so Alt-a opens this. Printed, never applied.
#
# One `nu -n` and nothing else: no plugin to hand over by path, no palette to
# source, no external program at all. That is the whole difference from v1's
# block, and from this module's own first attempt.
@search-terms agent notify browse help-setup keybinding zellij config alt-a floating
@example "how do I bind this?" { agent-notify browse help-setup }
export def help-setup []: nothing -> string {
    let root = $SELF | path dirname | path dirname
    ([ "Add this to the `normal` mode of ~/.config/zellij/config.kdl:"
       ""
       "  bind \"Alt a\" {"
       $"      Run \"nu\" \"-n\" \"-c\" \"use ($root); agent-notify browse\" {"
       "          name \"agents\""
       "          floating true"
       "          close_on_exit true"
       "          width \"90%\"; height \"90%\"; x \"5%\"; y \"5%\""
       "      }"
       "      SwitchToMode \"Normal\""
       "  }"
       ""
       "`-n` starts nu with no config, which is all this needs: the picker reads"
       "no settings and depends on no plugin and no external program."
       ""
       "A floating pane is not required — `agent-notify browse` runs perfectly"
       "well in place. The pane is only so that opening the picker does not"
       "disturb whatever you were looking at." ] | str join "\n")
}
