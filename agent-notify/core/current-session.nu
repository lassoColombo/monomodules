# "Which agent am I?" — asked by any command run from INSIDE an agent's session:
# the naming convention, a manual `report`, anything an agent invokes about
# itself.
#
# v1 never needed this. Its current-session was the zellij pane, which every
# child process inherits through `$ZELLIJ_PANE_ID`, so a command running in the
# pane could always say "me". Keying on the agent's own session (plan.md D11) is
# what makes zellij optional, and it takes that for granted away — a session id
# lives in the hook PAYLOAD, which a command typed by the agent never sees.
#
# The answer is an environment variable, and the generic one comes first on
# purpose: `AGENT_NOTIFY_ID` is the contract any agent can satisfy (export it
# once at startup and self-identification works, with nothing here needing to
# know the agent exists). The per-agent fallbacks below are a convenience for
# agents that already export something suitable — Claude sets
# CLAUDE_CODE_SESSION_ID, and it is exactly the `session_id` its hook payloads
# carry.

const AGENT_VARS = [
    [var                        agent];
    ["CLAUDE_CODE_SESSION_ID"   "claude"]
]

# This session's id and the agent that owns it, or null when unknowable.
export def resolve []: nothing -> any {
    let generic = $env.AGENT_NOTIFY_ID? | default ""
    if ($generic | is-not-empty) {
        return {id: $generic, agent: ($env.AGENT_NOTIFY_AGENT? | default "unknown")}
    }
    for c in $AGENT_VARS {
        let v = $env | get -o $c.var | default ""
        if ($v | is-not-empty) { return {id: $v, agent: $c.agent} }
    }
    null
}

# Same, but insist — for commands that are meaningless without an answer.
export def require []: nothing -> record {
    let me = resolve
    if ($me == null) {
        error make --unspanned {msg: ("agent-notify: cannot tell which agent this is — export "
            + "$env.AGENT_NOTIFY_ID (and optionally $env.AGENT_NOTIFY_AGENT), or pass --id")}
    }
    $me
}
