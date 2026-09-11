# Codex CLI. The second client, and the one that taught us what a half-wired
# agent costs — though not in the way it first appeared to.
#
# It began as an argv client built on `notify`, which was Codex's only
# integration point: one program, fired once, when a turn ends. That reached
# exactly ONE of the four states. A Codex record therefore read `awaiting` from
# its first turn until its last — true only during the window where it happened
# to coincide with reality, and wrong every second the agent was actually
# working. Nothing was malformed: `awaiting` is a legal state written by a legal
# client, and validation passed. The store simply has no way to say "I don't
# know", so a one-sided hook writes a confident fact that outlives its truth. A
# bar reading "2 agents waiting for you" is worth glancing at only if it is true.
#
# Codex has since grown a full hook system, shaped almost exactly like Claude
# Code's: one JSON object on stdin, `session_id` / `cwd` / `hook_event_name`,
# event → matcher group → `{type: "command", command}`, exit 2 to block. So this
# client now uses hooks, and `notify` is GONE rather than kept as a fallback —
# the two identify an agent differently (`notify` says `thread-id`, hooks say
# `session_id`) and nothing establishes that those are the same value. Running
# both would risk two records for one agent: the same pane counted as working and
# awaiting at once. One transport, one key.
#
# WHAT IS DIFFERENT FROM CLAUDE, and so why this is still its own file:
#
#   event name   comes from `hook_event_name` IN the payload rather than from our
#                argv. Codex puts it on every event, so reading it from the body
#                gives one command string for all six subscriptions and no way
#                for an argument to disagree with the key it is registered under.
#   attention    `PermissionRequest` — which Claude's client deliberately does
#                NOT subscribe to, because there `Notification` already covers it
#                and both would flap. Codex has no `Notification`, so this is the
#                signal rather than a duplicate of one.
#   wiring       `~/.codex/hooks.json`, in matcher groups.
#
# WRITTEN FROM DOCUMENTATION, not from observed traffic: Codex is not installed
# here, so unlike `claude.nu` this client has never seen a real payload. Two
# things to confirm against an install: that `SessionEnd` fires (one docs mirror
# omits it), and whether a subagent's tool events carry the PARENT's `session_id`
# the way Claude's do. Both fail ignore-shaped — a `SessionEnd` that never
# arrives leaves a stale record rather than a wrong one, and a subagent with its
# own id shows up as an extra agent rather than as corruption.

use ../core/event.nu
use ../core/payload.nu

const SELF = path self

export const INFO = {
    name: "codex"
    title: "Codex CLI"
    transport: "stdin-json"
    states: ["working" "awaiting" "needs-attention" "idle"]
}

# Named `ignored`, not `ignore`: a def shadows the builtin of that name for the
# whole file, and `main` below pipes to the builtin `ignore` (plan.md §10).
def ignored [why: string]: nothing -> record { {op: "ignore", why: $why} }

# Blank text becomes null, which the store reads as "delete this field" — the
# difference between "the turn said nothing" and "keep whatever it said last time".
def said [text: any]: nothing -> any {
    let t = $text | default "" | str trim
    if ($t | is-empty) { null } else { $t }
}

# `tool_input.description` is documented as an optional human-readable reason for
# the approval; the tool name is the worst case, and still tells you what is held up.
def permission-message [payload: record]: nothing -> string {
    let tool = $payload.tool_name? | default "a tool"
    let input = $payload.tool_input? | default {}
    let why = $input.description? | default "" | str trim
    if ($why | is-empty) { $"permission needed: ($tool)" } else { $"permission needed \(($tool)\): ($why)" }
}

def patch [id: string, changes: record, defaults?: record]: nothing -> record {
    { op: "patch", id: $id, changes: ({client: "codex"} | merge $changes)
      defaults: ($defaults | default {}) }
}

# `event` is the value of `hook_event_name`, spelled exactly as Codex spells it.
export def map [event: string, payload: record]: nothing -> record {
    let id = $payload.session_id? | default ""
    if ($id | is-empty) { return (ignored "payload carries no session_id") }

    match $event {
        # Identity only. `state` is a DEFAULT, not a change: Codex matches this
        # event on a `source` of startup, resume, clear or compact, so setting it
        # outright would knock a working agent back to idle on every compaction.
        "SessionStart" => (patch $id {
            cwd: ($payload.cwd? | default "")
            codex: {transcript_path: ($payload.transcript_path? | default "")}
        } {state: "idle"})

        "UserPromptSubmit" => (patch $id {state: "working"})
        "PostToolUse" => (patch $id {state: "working"})

        "Stop" => (patch $id {state: "awaiting", message: (said $payload.last_assistant_message?)})
        "PermissionRequest" => (patch $id {state: "needs-attention", message: (permission-message $payload)})

        "SessionEnd" => {op: "drop", id: $id}

        # Everything else is a deliberate no-op, `SubagentStop` above all: treating
        # it as the end of a turn would flash "awaiting" at you while the parent is
        # still working. `PreToolUse` would only repeat what `PostToolUse` says,
        # and the compaction pair says nothing about who is waiting for whom.
        _ => (ignored $"unhandled event '($event)'")
    }
}

# IMPORTED, not executed: nu evaluates a script-with-`main` twice, which costs
# ~9ms per event for nothing (plan.md §10). Takes no arguments at all, because the
# event arrives in the body along with everything else.
#
# THE HOOK MUST BE INVISIBLE. Codex reads exit codes — 2 denies the operation the
# hook fired for — so nothing here may fail and nothing may print.
export def main [] {
    try {
        let body = payload from-stdin
        event apply (map ($body.hook_event_name? | default "") $body) | ignore
    }
}

export def wiring []: nothing -> string {
    let events = ["SessionStart" "UserPromptSubmit" "PostToolUse" "Stop"
                  "PermissionRequest" "SessionEnd"]
    # An ABSOLUTE nu, not `nu`: a hook's PATH is not your shell's PATH.
    let cmd = $"($nu.current-exe) -n --no-std-lib -c 'use ($SELF); codex'"
    let hooks = $events | reduce --fold {} {|e, acc|
        $acc | merge {($e): [{hooks: [{type: "command", command: $cmd}]}]}
    }
    ([ "Add to ~/.codex/hooks.json, merging with any hooks already there:"
       ""
       ({hooks: $hooks} | to json --indent 2)
       ""
       "No `matcher` key, which matches every occurrence of each event. The same"
       "structure works as a [hooks] table in ~/.codex/config.toml — but use one"
       "file or the other: Codex loads both and warns when a single config layer"
       "carries both." ] | str join "\n")
}
