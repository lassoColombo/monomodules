# The Codex client: the payload mapping, and the hook entry end to end.
#
# Codex is not installed on this machine, so this suite is the only thing holding
# the client honest — it exercises the documented payloads rather than observed
# ones. What it CAN prove is everything on our side of the line: that the mapping
# is right, that the entry survives whatever arrives on its stdin, and that the
# store ends up saying what it should.
#
# The transport-swap checks are the point of the middle section: this client used
# to read argv and key on `thread-id`, and a leftover of that would be invisible
# except as an agent that never appears.

use ../../agent-notify
use ../clients/codex.nu
use ../core/event.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-codex")
const CLIENT = path self ../clients/codex.nu

# The fields every Codex hook carries, plus whatever the event adds.
def payload [extra: record = {}]: nothing -> record {
    { session_id: "sess-cx", transcript_path: "/tmp/cx.jsonl", cwd: "/Users/x/work"
      model: "gpt-5-codex", permission_mode: "default", turn_id: "t-3" } | merge $extra
}

# Exactly the command line hooks.json carries: the module imported with `-c`, and
# NO event argument — Codex names the event inside the body.
const HOOK_CMD = ["-n" "--no-std-lib" "-c"]

def hook-cmd []: nothing -> list<string> {
    $HOOK_CMD ++ [$"use ($CLIENT | to nuon); codex"]
}

def run-hook [event: string, body: record] {
    ($body | merge {hook_event_name: $event} | to json) | ^$nu.current-exe ...(hook-cmd) | complete
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # surface on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    # ── the mapping, as a pure function ──────────────────────────────────────
    let m = [
        (check "SessionStart carries identity, not state"
               (codex map "SessionStart" (payload) | get changes | columns | sort)
               ["client" "codex" "cwd"])
        (check "…and offers idle only as a create-time default"
               (codex map "SessionStart" (payload) | get defaults) {state: "idle"})
        (check "SessionStart keeps the transcript path in its own namespace"
               (codex map "SessionStart" (payload) | get changes.codex.transcript_path) "/tmp/cx.jsonl")

        (check "UserPromptSubmit → working"
               (codex map "UserPromptSubmit" (payload {prompt: "do the thing"}) | get changes.state)
               "working")
        (check "PostToolUse → working"
               (codex map "PostToolUse" (payload {tool_name: "Bash"}) | get changes.state) "working")

        (check "Stop → awaiting, with the message"
               (codex map "Stop" (payload {last_assistant_message: "Renamed and built."})
                | get changes.message) "Renamed and built.")
        (check "…and hands control back"
               (codex map "Stop" (payload) | get changes.state) "awaiting")
        (check "Stop with no message CLEARS rather than keeping a stale one"
               (codex map "Stop" (payload) | get changes.message) null)

        (check "a permission request needs attention"
               (codex map "PermissionRequest" (payload {tool_name: "Bash"}) | get changes.state)
               "needs-attention")
        (check "…and says what is held up"
               (codex map "PermissionRequest"
                        (payload {tool_name: "Bash", tool_input: {description: "delete the build dir"}})
                | get changes.message) "permission needed (Bash): delete the build dir")
        (check "…falling back to the tool name when it gives no reason"
               (codex map "PermissionRequest" (payload {tool_name: "apply_patch"}) | get changes.message)
               "permission needed: apply_patch")

        (check "SessionEnd drops" (codex map "SessionEnd" (payload {reason: "other"}) | get op) "drop")

        (check "SubagentStop is ignored, so a pane never flashes awaiting mid-turn"
               (codex map "SubagentStop" (payload) | get op) "ignore")
        (check "PreToolUse is ignored — PostToolUse already says working"
               (codex map "PreToolUse" (payload {tool_name: "Bash"}) | get op) "ignore")
        (check "a compaction says nothing about who is waiting"
               (codex map "PreCompact" (payload) | get op) "ignore")

        (check "identity is the snake_case session_id the hooks carry"
               (codex map "Stop" (payload) | get id) "sess-cx")
        (check "a payload with no session_id is ignored"
               (codex map "Stop" {} | get op) "ignore")
        (check "every patch names its client"
               (codex map "Stop" (payload) | get changes.client) "codex")
    ]

    # ── the transport swap, which nothing else would catch ───────────────────
    # A `notify` payload has a `thread-id` and no `session_id`, so the hooks
    # client must not recognise it at all: half a client would leave an agent
    # that simply never appears.
    let notify_body = { type: "agent-turn-complete", "thread-id": "th-77"
                        "last-assistant-message": "Did the thing." }
    let t = [
        (check "a notify-shaped payload no longer maps"
               (codex map "agent-turn-complete" $notify_body | get op) "ignore")
        (check "…and its event name is not one we handle"
               (codex map "Stop" $notify_body | get op) "ignore")
    ]

    # ── create-only defaults, through the real sequence ──────────────────────
    event apply (codex map "SessionStart" (payload))
    event apply (codex map "UserPromptSubmit" (payload))
    let resumed = event apply (codex map "SessionStart" (payload {source: "compact"}))
    let d = [
        (check "SessionStart then a prompt leaves it working"
               (agent-notify store get "sess-cx" | get state) "working")
        (check "SessionStart after a compaction does NOT knock it back to idle"
               $resumed.changed false)
    ]

    # ── the entry, exactly as hooks.json will run it ─────────────────────────
    let e1 = run-hook "Stop" (payload {last_assistant_message: "Hooks work."})
    let rec = agent-notify store get "sess-cx"
    let e = [
        (check "the hook exits 0" $e1.exit_code 0)
        (check "…and prints nothing at all" ($e1.stdout + $e1.stderr) "")
        (check "the store saw the turn end" $rec.state "awaiting")
        (check "…with the message" $rec.message "Hooks work.")
        (check "…and under the right client" $rec.client "codex")
        (check "a malformed body cannot break the hook"
               (("not json" | ^$nu.current-exe ...(hook-cmd) | complete).exit_code) 0)
        (check "a body with no hook_event_name cannot break it"
               ((("{}" | ^$nu.current-exe ...(hook-cmd) | complete)).exit_code) 0)
        (check "an event Codex has not invented yet cannot break it"
               ((run-hook "NoSuchEvent" (payload)).exit_code) 0)
    ]
    let ended = run-hook "SessionEnd" (payload {reason: "other"})
    let f = [
        (check "SessionEnd forgets the agent" (agent-notify store get "sess-cx") null)
        (check "…quietly" $ended.exit_code 0)
    ]

    # One store, and a client that names itself in every record it writes.
    let c = [ (check "every record here came from codex"
                     (agent-notify store list | get client | uniq) []) ]

    summarise ($m ++ $t ++ $d ++ $e ++ $f ++ $c) --title "codex client"
}
