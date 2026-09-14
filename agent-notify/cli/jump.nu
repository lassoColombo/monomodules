# `agent-notify jump <who>` — go to an agent, wherever it lives.
#
# THE COMMAND IS THE FACADE'S, NOT ZELLIJ'S (plan.md D74). It was
# `integrations/zellij/jump.nu` for as long as zellij was the only integration
# agents run inside, which made a general idea look like a zellij one. It is
# three steps and none of them names a tool:
#
#   find-session      which agent did you mean          core/find-session.nu
#   container-of      which integration has it          the registry
#   focus-session     ask that integration to go there  the container's own
#
# So `agent-notify jump` works for tmux the day a tmux `session-container.nu`
# exists, and this file does not change.
#
# IT IS COLD. Nothing dispatches to it and `displays:` does not turn it on — it
# runs because you ran it (D47). That is also why the registry it reaches can
# afford to drag `core/session-store.nu` and `core/config.nu` behind it: no hook
# is ever in this import cone (D71).

use ../core/find-session.nu
use ../integrations/session-containers.nu

# The agent and the integration that has it, or a sentence saying why not.
#
# An agent no container claims is the ordinary case for an agent that has never
# been seen in a pane — a bare terminal, a script — so it gets a sentence rather
# than a crash, and the sentence names the agent.
#
# No return-type signature: a def annotated with one cannot END in `error make`
# (plan.md §10).
def located [who: string] {
    let rec = find-session $who
    let container = session-containers container-of $rec
    if ($container == null) {
        let label = $rec.name? | default ($rec.id? | default $who)
        error make --unspanned {msg: ($"agent-notify: '($label)' is not inside anything that can "
            + "be jumped to \(it has never been seen in a pane)")}
    }
    {rec: $rec, container: $container}
}

# Focus the agent's pane. Silent on success, the way a command that moved your
# screen should be: you are looking at the result.
@search-terms agent notify jump focus goto pane session go to agent
@example "go to an agent by name" { agent-notify jump build-the-thing }
@example "…or by the start of its id" { agent-notify jump 6923c0bc }
@example "what would that run, without running it?" { agent-notify jump build-the-thing --dry-run }
export def main [
    who: string     # an agent's id, a unique prefix of one, or its name
    --dry-run       # print the commands instead of running them
] {
    let it = located $who
    if $dry_run { return (do $it.container.focus-session-argv $it.rec) }
    do $it.container.focus-session $it.rec
}
