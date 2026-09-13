# What an agent says about ITSELF, from inside its own session.
#
# `store patch` can already express all of this, but it needs an id, and an agent
# running a command in its own shell does not have one to hand — the session id
# lives in the hook payload, not the environment (core/identity.nu explains why
# and how that is answered). These two verbs close that gap, and they are the
# reason plan.md P5 is a usable interface rather than a claim: any agent that can
# run a command and export one variable can report itself.
#
#   $env.AGENT_NOTIFY_ID = "whatever-identifies-me"
#   agent-notify report --state working
#   agent-notify name "fix-the-parser"

use ../core/identity.nu
use ../core/event.nu

def target [given: any]: nothing -> record {
    if ($given != null) { return {id: $given, client: "unknown"} }
    identity require
}

# Report this agent's state. The everyday entry for anything that is not Claude
# Code — a script, a cron job, another CLI agent.
#
# `--client` overrides what identity resolution guessed, which matters on the
# generic path: `$env.AGENT_NOTIFY_ID` says who you are but not what you are.
@search-terms agent notify state working awaiting attention report
@example "a script reporting itself" { agent-notify report --state working --client nightly }
@example "…and handing back control" { agent-notify report --state awaiting --message "3 files changed" }
export def report [
    --state: string      # working | awaiting | needs-attention | idle
    --id: string         # override identity resolution
    --client: string     # override the client name
    --name: string       # a deliberate, human-meaningful name
    --message: string    # what you want to say to whoever is watching
    --cwd: string
]: nothing -> record {
    let me = target $id
    mut changes = {client: ($client | default $me.client)}
    if ($state != null) { $changes = ($changes | merge {state: $state}) }
    if ($name != null) { $changes = ($changes | merge {name: $name}) }
    if ($message != null) { $changes = ($changes | merge {message: $message}) }
    if ($cwd != null) { $changes = ($changes | merge {cwd: $cwd}) }
    event apply {op: "patch", id: $me.id, changes: $changes, defaults: {state: "idle"}}
}

# Name this session — the deliberate act that fixes what every surface calls it.
#
# Nothing else can move the displayed name: with no name set, surfaces fall back
# to the cwd's basename, and that fallback applies only in the absence of a name.
# So the name is free to change and, in practice, does not (plan.md D12).
@search-terms agent notify name rename title session
@example "name the session for the work it is doing" { agent-notify name "explain-agent-notify" }
export def name [
    value: string
    --id: string
]: nothing -> record {
    let me = target $id
    event apply {op: "patch", id: $me.id, changes: {client: $me.client, name: $value}
                 defaults: {state: "idle"}}
}

# This agent has stopped — what a client calls when its session ends. The record
# is filed away rather than destroyed, so reporting the same id again later
# brings its name back (core/store.nu).
@search-terms agent notify end session clear forget archive
export def "report end" [--id: string]: nothing -> record {
    event apply {op: "drop", id: (target $id | get id)}
}
