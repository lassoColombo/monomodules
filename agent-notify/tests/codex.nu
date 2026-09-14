# The Codex agent: the payload mapping, and the hook entry end to end.
#
# Codex is not installed on this machine, so this suite is the only thing
# holding the agent honest — it exercises the documented payloads rather than
# observed ones. What it CAN prove is everything on our side of the line: that
# the mapping is right, that the entry survives whatever arrives on its stdin,
# and that the session-store ends up saying what it should.
#
# The transport-swap checks are the point of the middle section: this agent
# used to read argv and key on `thread-id`, and a leftover of that would be
# invisible except as an agent that never appears.

use ../../agent-notify
use ../agents/codex.nu
use ../core/session-change.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests-codex")
const AGENT = path self ../agents/codex.nu

# The fields every Codex hook carries, plus whatever the event adds.
def hook-input [extra: record = {}]: nothing -> record {
    { session_id: "sess-cx", transcript_path: "/tmp/cx.jsonl", cwd: "/Users/x/work"
      model: "gpt-5-codex", permission_mode: "default", turn_id: "t-3" } | merge $extra
}

# Exactly the command line hooks.json carries: the module imported with `-c`,
# and NO event argument — Codex names the event inside the body.
const HOOK_CMD = ["-n" "--no-std-lib" "-c"]

def hook-cmd []: nothing -> list<string> {
    $HOOK_CMD ++ [$"use ($AGENT | to nuon); codex"]
}

def run-hook [event: string, body: record] {
    ($body | merge {hook_event_name: $event} | to json) | ^$nu.current-exe ...(hook-cmd) | complete
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # display on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    # ── the mapping, as a pure function ───────────────────────────────────────
    let m = [
        (check "SessionStart carries current-session, not state"
               (codex to-session-change "SessionStart" (hook-input) | get changes | columns | sort)
               ["agent" "codex" "cwd"])
        (check "…and offers idle only as a create-time default"
               (codex to-session-change "SessionStart" (hook-input) | get defaults) {state: "idle"})
        (check "SessionStart keeps the transcript path in its own namespace"
               (codex to-session-change "SessionStart" (hook-input) | get changes.codex.transcript_path) "/tmp/cx.jsonl")

        (check "UserPromptSubmit → working"
               (codex to-session-change "UserPromptSubmit" (hook-input {prompt: "do the thing"}) | get changes.state)
               "working")
        (check "PostToolUse → working"
               (codex to-session-change "PostToolUse" (hook-input {tool_name: "Bash"}) | get changes.state) "working")

        (check "Stop → awaiting, with the message"
               (codex to-session-change "Stop" (hook-input {last_assistant_message: "Renamed and built."})
                | get changes.message) "Renamed and built.")
        (check "…and hands control back"
               (codex to-session-change "Stop" (hook-input) | get changes.state) "awaiting")
        (check "Stop with no message CLEARS rather than keeping a stale one"
               (codex to-session-change "Stop" (hook-input) | get changes.message) null)

        (check "a permission request needs attention"
               (codex to-session-change "PermissionRequest" (hook-input {tool_name: "Bash"}) | get changes.state)
               "needs-attention")
        (check "…and says what is held up"
               (codex to-session-change "PermissionRequest"
                        (hook-input {tool_name: "Bash", tool_input: {description: "delete the build dir"}})
                | get changes.message) "permission needed (Bash): delete the build dir")
        (check "…falling back to the tool name when it gives no reason"
               (codex to-session-change "PermissionRequest" (hook-input {tool_name: "apply_patch"}) | get changes.message)
               "permission needed: apply_patch")

        (check "SessionEnd drops" (codex to-session-change "SessionEnd" (hook-input {reason: "other"}) | get change-kind) "end")

        (check "SubagentStop is ignored, so a pane never flashes awaiting mid-turn"
               (codex to-session-change "SubagentStop" (hook-input) | get change-kind) "ignore")
        (check "PreToolUse is ignored — PostToolUse already says working"
               (codex to-session-change "PreToolUse" (hook-input {tool_name: "Bash"}) | get change-kind) "ignore")
        (check "a compaction says nothing about who is waiting"
               (codex to-session-change "PreCompact" (hook-input) | get change-kind) "ignore")

        (check "current-session is the snake_case session_id the hooks carry"
               (codex to-session-change "Stop" (hook-input) | get id) "sess-cx")
        (check "a payload with no session_id is ignored"
               (codex to-session-change "Stop" {} | get change-kind) "ignore")
        (check "every patch names its agent"
               (codex to-session-change "Stop" (hook-input) | get changes.agent) "codex")
    ]

    # ── the transport swap, which nothing else would catch ────────────────────
    # A `notify` payload has a `thread-id` and no `session_id`, so the hooks
    # module must not recognise it at all: half a module would leave an agent
    # that simply never appears.
    let notify_body = { type: "agent-turn-complete", "thread-id": "th-77"
                        "last-assistant-message": "Did the thing." }
    let t = [
        (check "a notify-shaped payload no longer maps"
               (codex to-session-change "agent-turn-complete" $notify_body | get change-kind) "ignore")
        (check "…and its event name is not one we handle"
               (codex to-session-change "Stop" $notify_body | get change-kind) "ignore")
    ]

    # ── create-only defaults, through the real sequence ───────────────────────
    session-change apply (codex to-session-change "SessionStart" (hook-input))
    session-change apply (codex to-session-change "UserPromptSubmit" (hook-input))
    let resumed = session-change apply (codex to-session-change "SessionStart" (hook-input {source: "compact"}))
    let d = [
        (check "SessionStart then a prompt leaves it working"
               (agent-notify session-store get "sess-cx" | get state) "working")
        (check "SessionStart after a compaction does NOT knock it back to idle"
               $resumed.changed false)
    ]

    # ── the entry, exactly as hooks.json will run it ──────────────────────────
    let e1 = run-hook "Stop" (hook-input {last_assistant_message: "Hooks work."})
    let rec = agent-notify session-store get "sess-cx"
    let e = [
        (check "the hook exits 0" $e1.exit_code 0)
        (check "…and prints nothing at all" ($e1.stdout + $e1.stderr) "")
        (check "the session-store saw the turn end" $rec.state "awaiting")
        (check "…with the message" $rec.message "Hooks work.")
        (check "…and under the right agent" $rec.agent "codex")
        (check "a malformed body cannot break the hook"
               (("not json" | ^$nu.current-exe ...(hook-cmd) | complete).exit_code) 0)
        (check "a body with no hook_event_name cannot break it"
               ((("{}" | ^$nu.current-exe ...(hook-cmd) | complete)).exit_code) 0)
        (check "an event Codex has not invented yet cannot break it"
               ((run-hook "NoSuchEvent" (hook-input)).exit_code) 0)
    ]
    let ended = run-hook "SessionEnd" (hook-input {reason: "other"})
    let f = [
        (check "SessionEnd forgets the agent" (agent-notify session-store get "sess-cx") null)
        (check "…quietly" $ended.exit_code 0)
    ]

    # One session-store, and an agent that names itself in every record it
    # writes.
    let c = [ (check "every record here came from codex"
                     (agent-notify session-store list | get agent | uniq) []) ]

    summarise ($m ++ $t ++ $d ++ $e ++ $f ++ $c) --title "codex agent"
}
