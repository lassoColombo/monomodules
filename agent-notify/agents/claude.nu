# Claude Code. One file, one agent — the whole integration, and the only place
# in the module that knows this agent exists.
#
# Every agent module exposes the same three things:
#   INFO     what it is, for `agent-notify agents`
#   to-operation
#            PURE: (event, hook_input) → a session-store operation. Where the
#            thinking is, and what the tests exercise — no session-store, no
#            hook, no agent required.
#   main     the entry the agent actually runs. Owns the parts that are peculiar
#            to this agent: where the payload comes from, what to print back, what
#            exit code to leave behind.
#
# Nothing registers this file. Claude's own settings.json names it directly, so
# an agent module works the moment it exists (agents/mod.nu lists it for discovery
# only).
#
# WHAT MAPS TO WHAT, and the three judgements that are not obvious:
#
# 1. SUBAGENTS fold into their parent, for free. Tool events fire inside subagents
#    too, but they carry the PARENT's `session_id` (plus `agent_id`/`agent_type`
#    identifying the subagent), so a subagent's tool call marks the parent
#    working — which is exactly right: the pane is busy. v1 got the same result by
#    keying on the pane; here it falls out of the payload. The corollary is that
#    `SubagentStop` must be IGNORED: treating it as the end of a turn would flash
#    "awaiting" at you while the parent is still working.
#
# 2. `Stop` CLEARS the message when the payload has none, rather than leaving the
#    previous turn's text in place, because a stale answer shown against a fresh
#    turn is worse than no answer. `working` does NOT clear it: the last message
#    is a fact about the last turn and does not stop being true because work
#    resumed — whether to show it is a display's decision, not ours.
#
# 3. `StopFailure` is a state v1 could not express at all: the turn died on an API
#    error (rate limit, overload, auth) rather than finishing. That is the case
#    where you genuinely need to go and look, so it maps to needs-attention with
#    the reason as its message.
#
# NOT subscribed, deliberately: `PermissionRequest` (Notification already covers
# it, and both would flap), `SubagentStop` (see above), and everything else.

use ../core/operation.nu
use ../core/hook-input.nu
use ../core/proc.nu

const SELF = path self

export const INFO = {
    name: "claude"
    title: "Claude Code"
    transport: "stdin-json"
    states: ["working" "awaiting" "needs-attention" "idle"]
    # How to recognise the agent among our own ancestors, so a killed session
    # can be proved dead later (core/proc.nu). Claude does not tell us its pid.
    process: "claude"
}

# Notification types that genuinely mean "the agent needs YOU". The others —
# idle nudges, auth success, completion notices, quota chatter — must never
# escalate.
const ATTN_NOTIFICATIONS = [
    "permission_prompt"
    "elicitation_dialog"
    "elicitation_url_dialog"
    "agent_needs_input"
]

# Named `ignored`, not `ignore`: a def shadows the builtin of that name for the
# whole file, and the very next line pipes to the builtin `ignore` (plan.md
# §10).
def ignored [why: string]: nothing -> record { {operation-kind: "ignore", why: $why} }

# Blank text becomes null, which the session-store reads as "delete this field"
# — the difference between "the turn said nothing" and "keep whatever it said
# last time".
def said [text: any]: nothing -> any {
    let t = $text | default "" | str trim
    if ($t | is-empty) { null } else { $t }
}

def failure-message [hook_input: record]: nothing -> string {
    let kind = $hook_input.error_type? | default "unknown"
    let detail = $hook_input.error_message? | default "" | str trim
    if ($detail | is-empty) { $"turn failed: ($kind)" } else { $"turn failed \(($kind)\): ($detail)" }
}

def patch [id: string, changes: record, defaults?: record]: nothing -> record {
    { operation-kind: "patch", id: $id, changes: ({agent: "claude"} | merge $changes)
      defaults: ($defaults | default {}) }
}

# `event` is the hook name exactly as Claude Code spells it.
export def to-operation [event: string, hook_input: record]: nothing -> record {
    let id = $hook_input.session_id? | default ""
    if ($id | is-empty) { return (ignored "payload carries no session_id") }

    match $event {
        # Identity only. `state` is a DEFAULT, not a change: SessionStart also
        # fires on resume, clear, compact and fork, and setting it outright
        # would knock a working agent back to idle every time the context
        # compacted.
        "SessionStart" => (patch $id {
            cwd: ($hook_input.cwd? | default "")
            claude: {transcript_path: ($hook_input.transcript_path? | default "")}
        } {state: "idle"})

        "UserPromptSubmit" => (patch $id {state: "working"})
        "PostToolUse" => (patch $id {state: "working"})

        "Stop" => (patch $id {state: "awaiting", message: (said $hook_input.last_assistant_message?)})
        "StopFailure" => (patch $id {state: "needs-attention", message: (failure-message $hook_input)})

        "Notification" => {
            let kind = $hook_input.notification_type? | default ""
            # An unrecognised or absent type is allowed through: a notification
            # we have never heard of is more likely to want you than not.
            if ($kind | is-not-empty) and ($kind not-in $ATTN_NOTIFICATIONS) {
                ignored $"notification '($kind)' does not need attention"
            } else {
                patch $id {state: "needs-attention", message: (said $hook_input.message?)}
            }
        }

        # The cwd is a fact that moves, and the display name falls back to its
        # basename, so it is worth keeping straight.
        "CwdChanged" => (patch $id {cwd: ($hook_input.cwd? | default "")})

        "SessionEnd" => {operation-kind: "end", id: $id}

        _ => (ignored $"unhandled event '($event)'")
    }
}

# IMPORTED, not executed. Running this file as a script would work and costs
# ~9ms more per event (29.3ms against 20.4ms, measured): nu's path for a script
# with a `main` and arguments evaluates twice — a synthetic command line on top
# of the file itself — and that second pass is worth ~7.5ms even when `main`
# does nothing. An absolute path in the `use` means no `-I` is needed.
#
# THE HOOK MUST BE INVISIBLE. Claude Code reads a hook's exit code and a
# non-zero one can block the very tool call that triggered it, so nothing here
# may fail and nothing may print. A broken notifier is a nuisance; a notifier
# that blocks your agent is a catastrophe.
export def main [event: string] {
    try {
        let operation = to-operation $event (hook-input from-stdin)
        operation apply (if $event in ["SessionStart" "UserPromptSubmit"] { with-proc $operation } else { $operation }) | ignore
    }
}

# The agent's process. SessionStart is where it can be NEW; UserPromptSubmit is
# where a missing one is recovered.
#
# The retry matters more than it looks. Without it a missing pid is PERMANENT:
# if the walk fails once, or the session predates this code, that agent can
# never be proved dead for the rest of its life, and every display shows it
# forever. Once per turn it is simply looked up again.
#
# No session-store read is needed to decide whether it is missing, because
# attaching it is IDEMPOTENT: a pid does not change within a session, so a
# second attach produces an identical record, `changed` is false, and nothing is
# written or painted. The whole cost is the ~10ms walk, once per turn — against
# the hundreds of tool calls that never pay it. Kept out of `map` so `map` stays
# a pure function of its payload.
def with-proc [operation: record]: nothing -> record {
    if ($operation.operation-kind? != "patch") { return $operation }
    let p = proc find $INFO.process
    if $p == null { return $operation }
    $operation | upsert changes ($operation.changes | merge {proc: $p})
}

export def help-setup []: nothing -> string {
    let events = ["SessionStart" "UserPromptSubmit" "PostToolUse" "Stop" "StopFailure"
                  "Notification" "CwdChanged" "SessionEnd"]
    let hooks = $events | reduce --fold {} {|e, acc|
        $acc | merge {($e): [{hooks: [{
            type: "command"
            # An ABSOLUTE nu, not `nu`: a hook's PATH is not your shell's PATH,
            # and v1 had to `export PATH=/opt/homebrew/bin:$PATH` at the top of
            # its glue script for exactly this reason.
            command: $"($nu.current-exe) -n --no-std-lib -c 'use ($SELF); claude ($e)'"
        }]}]}
    }
    ([ "Add to ~/.claude/settings.json, merging with any hooks already there:"
       ""
       ({hooks: $hooks} | to json --indent 2) ] | str join "\n")
}
