# `agent-notify jump <who>` — go to an agent, wherever it lives.
#
# THE COMMAND IS THE FACADE'S, NOT ZELLIJ'S (plan.md D75). It was
# `integrations/zellij/jump.nu` for as long as zellij was the only integration
# agents run inside, which made a general idea look like a zellij one. It is two
# steps and neither names a tool:
#
#   find-session    which agent did you mean       core/find-session.nu
#   focus-session   walk the path to it            the registry
#
# A SESSION IS AT A PATH, NOT IN A PLACE (D77). Nothing here knows whether that
# path is one container long or three — the registry walks it, outermost first,
# and this file would not change if aerospace, Ghostty and tmux all arrived
# tomorrow. Which is the same reason it does not change for tmux today.
#
# IT IS COLD. Nothing dispatches to it and `displays:` does not turn it on — it
# runs because you ran it (D47). That is also why the registry it reaches can
# afford to drag `core/session-store.nu` and `core/config.nu` behind it: no hook
# is ever in this import cone (D72).

use ../core/find-session.nu
use ../integrations/session-containers.nu

# The agent, once it is established that there is somewhere to take you.
#
# An agent no container claims is the ordinary case for one that has never been
# seen in a pane — a bare terminal, a script — so it gets a sentence rather than
# a crash, and the sentence names the agent.
#
# No return-type signature: a def annotated with one cannot END in `error make`
# (plan.md §10).
def reachable [who: string] {
    let rec = find-session $who
    if (session-containers containers-of $rec | is-empty) {
        let label = $rec.name? | default ($rec.id? | default $who)
        error make --unspanned {msg: ($"agent-notify: '($label)' is not inside anything that can "
            + "be jumped to \(it has never been seen in a pane)")}
    }
    $rec
}

# Focus the agent's pane. Silent on success, the way a command that moved your
# screen should be: you are looking at the result.
@search-terms agent notify jump focus goto pane session go to agent
@example "go to an agent by name" { agent-notify jump build-the-thing }
@example "…or by the start of its id" { agent-notify jump 6923c0bc }
@example "what would the whole path run?" { agent-notify jump build-the-thing --dry-run }
export def main [
    who: string     # an agent's id, a unique prefix of one, or its name
    --dry-run       # print the commands instead of running them
] {
    let rec = reachable $who
    if $dry_run { return (session-containers focus-session-argv $rec) }
    session-containers focus-session $rec
}
