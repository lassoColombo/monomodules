# What an agent says about ITSELF, from inside its own session.
#
# `session-store patch` can already express all of this, but it needs an id, and
# an agent running a command in its own shell does not have one to hand — the
# session id lives in the hook payload, not the environment
# (core/current-session.nu explains why and how that is answered). These two
# verbs close that gap, and they are the reason plan.md P5 is a usable interface
# rather than a claim: any agent that can run a command and export one variable
# can report itself.
#
#   $env.AGENT_NOTIFY_ID = "whatever-identifies-me"
#   agent-notify report --state working
#   agent-notify name "fix-the-parser"

use ../core/current-session.nu
use ../core/operation.nu
use ../core/session-store.nu

def target [given: any]: nothing -> record {
    if ($given != null) { return {id: $given, client: "unknown"} }
    current-session require
}

# Report this agent's state. The everyday entry for anything that is not Claude
# Code — a script, a cron job, another CLI agent.
#
# `--client` overrides what current-session resolution guessed, which matters on
# the generic path: `$env.AGENT_NOTIFY_ID` says who you are but not what you
# are.
@search-terms agent notify state working awaiting attention report
@example "a script reporting itself" { agent-notify report --state working --client nightly }
@example "…and handing back control" { agent-notify report --state awaiting --message "3 files changed" }
export def report [
    --state: string      # working | awaiting | needs-attention | idle
    --id: string         # override current-session resolution
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
    operation apply {operation-kind: "patch", id: $me.id, changes: $changes, defaults: {state: "idle"}}
}

# Name this session — the deliberate act that fixes what every display calls it.
#
# Nothing else can move the displayed name: with no name set, displays fall back
# to the cwd's basename, and that fallback applies only in the absence of a
# name. So the name is free to change and, in practice, should not (plan.md
# D12).
#
# `--if-unnamed` IS WHAT MAKES THIS SAFE TO RUN AT EVERY SESSION START, resumed
# ones included. A resumed session keeps the name it had — `SessionEnd` files
# the record away and a resume hands it back (D59) — so naming it again would
# only make a stable name unstable, and the name is how a session is recognised
# on the bar and in the picker. With the flag, a name that is already there is
# left alone and nothing is written at all.
#
# It cannot be expressed as a create-only `default`: a fresh session's record
# already exists by the time this runs (SessionStart made it), so a default
# would never apply and a fresh session would never get named.
@search-terms agent notify name rename title session
@example "name the session for the work it is doing" { agent-notify name "explain-agent-notify" }
@example "…at every session start, resumed ones included" { agent-notify name "some-name" --if-unnamed }
export def name [
    value: string
    --id: string
    --if-unnamed        # leave an existing name alone; write only when there is none
]: nothing -> record {
    let me = target $id
    if $if_unnamed {
        let rec = session-store read $me.id
        let have = ($rec | default {} | get -o name | default "") | str trim
        if ($have | is-not-empty) { return {changed: false, before: $rec, after: $rec} }
    }
    operation apply {operation-kind: "patch", id: $me.id, changes: {client: $me.client, name: $value}
                 defaults: {state: "idle"}}
}

# This agent has stopped — what a client calls when its session ends. The record
# is filed away rather than destroyed, so reporting the same id again later
# brings its name back (core/session-store.nu).
@search-terms agent notify end session clear forget archive
export def "report end" [--id: string]: nothing -> record {
    operation apply {operation-kind: "end", id: (target $id | get id)}
}
