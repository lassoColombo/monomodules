# Step 2 — the Claude client: the payload mapping, and the hook entry end to end.
#
# The mapping is a pure function, so most of this needs no store, no agent and no
# hook: hand it a payload, read back the operation. The last section then runs the
# real entry script with real JSON on its stdin, which is the only way to know
# that the thing Claude Code will actually execute works.

use ../../agent-notify2
use ../clients/claude.nu
use ../core/event.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-claude")
const CLIENT = path self ../clients/claude.nu

# A payload with the fields every hook carries, plus whatever the event adds.
def payload [extra: record = {}]: nothing -> record {
    { session_id: "sess-abc", transcript_path: "/tmp/t.jsonl", cwd: "/Users/x/projects/thing"
      permission_mode: "default" } | merge $extra
}

# Exactly the command line settings.json carries — the module imported with `-c`,
# not the file run as a script (see clients/claude/hook.nu for why that matters).
def hook-cmd [event: string]: nothing -> list<string> {
    ["-n" "--no-std-lib" "-c" $"use ($CLIENT | to nuon); claude ($event)"]
}

def run-hook [event: string, body: record] {
    ($body | to json) | ^$nu.current-exe ...(hook-cmd $event) | complete
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP

    # ── the mapping, as a pure function ──────────────────────────────────────
    let m = [
        (check "SessionStart carries identity, not state"
               (claude map "SessionStart" (payload) | get changes | columns | sort)
               ["claude" "client" "cwd"])
        (check "…and offers idle only as a create-time default"
               (claude map "SessionStart" (payload) | get defaults) {state: "idle"})
        (check "SessionStart keeps the transcript path in its own namespace"
               (claude map "SessionStart" (payload) | get changes.claude.transcript_path) "/tmp/t.jsonl")

        (check "UserPromptSubmit → working"
               (claude map "UserPromptSubmit" (payload) | get changes.state) "working")
        (check "PostToolUse → working"
               (claude map "PostToolUse" (payload {tool_name: "Bash"}) | get changes.state) "working")
        (check "a SUBAGENT's tool call reports the PARENT session"
               (claude map "PostToolUse" (payload {agent_id: "sub-1", agent_type: "Explore"}) | get id)
               "sess-abc")
        (check "SubagentStop is ignored, so a pane never flashes awaiting mid-turn"
               (claude map "SubagentStop" (payload {last_assistant_message: "done"}) | get op) "ignore")

        (check "Stop → awaiting, with the message"
               (claude map "Stop" (payload {last_assistant_message: "All green."}) | get changes.message)
               "All green.")
        (check "Stop with no message CLEARS rather than keeping a stale one"
               (claude map "Stop" (payload) | get changes.message) null)

        (check "StopFailure → needs-attention"
               (claude map "StopFailure" (payload {error_type: "rate_limit"}) | get changes.state)
               "needs-attention")
        (check "…and says why"
               (claude map "StopFailure" (payload {error_type: "overloaded", error_message: "try later"})
                | get changes.message)
               "turn failed (overloaded): try later")

        (check "a permission prompt needs attention"
               (claude map "Notification" (payload {notification_type: "permission_prompt", message: "may I?"})
                | get changes.state) "needs-attention")
        (check "an idle nudge does NOT"
               (claude map "Notification" (payload {notification_type: "idle_prompt", message: "still there?"})
                | get op) "ignore")
        (check "nor does a completion notice"
               (claude map "Notification" (payload {notification_type: "agent_completed"}) | get op) "ignore")
        (check "an unrecognised notification is allowed through"
               (claude map "Notification" (payload {message: "something new"}) | get changes.state)
               "needs-attention")

        (check "CwdChanged keeps the cwd straight"
               (claude map "CwdChanged" (payload {cwd: "/elsewhere"}) | get changes.cwd) "/elsewhere")
        (check "SessionEnd drops" (claude map "SessionEnd" (payload) | get op) "drop")
        (check "an unhandled event is a deliberate no-op"
               (claude map "PreCompact" (payload) | get op) "ignore")
        (check "a payload with no session_id is ignored"
               (claude map "Stop" {} | get op) "ignore")
        (check "every patch names its client"
               (claude map "Stop" (payload) | get changes.client) "claude")
    ]

    # ── create-only defaults, through the real sequence ──────────────────────
    event apply (claude map "SessionStart" (payload))
    event apply (claude map "UserPromptSubmit" (payload))
    let resumed = event apply (claude map "SessionStart" (payload {source: "compact"}))
    let d = [
        (check "SessionStart then a prompt leaves it working"
               (agent-notify2 store get "sess-abc" | get state) "working")
        (check "SessionStart after a compaction does NOT knock it back to idle"
               $resumed.changed false)
    ]

    # ── the entry script, exactly as Claude Code will run it ─────────────────
    let e1 = run-hook "Stop" (payload {last_assistant_message: "Step 2 works."})
    let rec = agent-notify2 store get "sess-abc"
    let e = [
        (check "the hook exits 0" $e1.exit_code 0)
        (check "…and prints nothing at all" ($e1.stdout + $e1.stderr) "")
        (check "the store saw it" $rec.state "awaiting")
        (check "…with the message" $rec.message "Step 2 works.")
        (check "a malformed body cannot break the hook"
               (("not json" | ^$nu.current-exe ...(hook-cmd "Stop") | complete).exit_code) 0)
        (check "an unknown event cannot break the hook"
               ((run-hook "NoSuchEvent" (payload)).exit_code) 0)
    ]
    let ended = run-hook "SessionEnd" (payload {reason: "logout"})
    let f = [
        (check "SessionEnd forgets the agent" (agent-notify2 store get "sess-abc") null)
        (check "…quietly" $ended.exit_code 0)
    ]

    # ── what an agent says about itself, resolved from the environment ───────
    $env.AGENT_NOTIFY_ID = "self-test-1"
    $env.AGENT_NOTIFY_CLIENT = "nightly"
    agent-notify2 report --state working
    agent-notify2 name "build-the-thing"
    let self_rec = agent-notify2 store get "self-test-1"
    let s = [
        (check "an agent can report itself with no id at all" $self_rec.state "working")
        (check "…under the client it declared" $self_rec.client "nightly")
        (check "…and name itself" $self_rec.name "build-the-thing")
        (check "naming again with the same name changes nothing"
               (agent-notify2 name "build-the-thing" | get changed) false)
        (check "a rename is allowed — the name is not frozen"
               (agent-notify2 name "build-something-else" | get changed) true)
        (check "report end forgets it"
               (agent-notify2 report end | get changed) true)
    ]

    # ...and without any way to know who we are, the error says what to do.
    hide-env AGENT_NOTIFY_ID
    hide-env CLAUDE_CODE_SESSION_ID
    let s2 = [
        (check-err "an unidentifiable caller is told how to identify itself"
                   "export $env.AGENT_NOTIFY_ID" {|| agent-notify2 report --state working })
    ]

    # ── the agent's process, recorded once ───────────────────────────────────
    # Deterministic because AGENT_NOTIFY_PID short-circuits the walk: the suite
    # does not have to be running inside Claude for this to mean something.
    $env.AGENT_NOTIFY_PID = ($nu.pid | into string)
    run-hook "SessionStart" (payload {session_id: "proc-1"}) | ignore
    run-hook "PostToolUse" (payload {session_id: "proc-2", tool_name: "Bash"}) | ignore
    let p = [
        (check "the mapping stays pure — it looks up no process"
               ("proc" in (claude map "SessionStart" (payload) | get changes | columns)) false)
        (check "SessionStart records the agent's process, so a kill can be proved later"
               (agent-notify2 store get "proc-1" | get proc.pid) $nu.pid)
        (check "…and no other event pays the ~10ms walk"
               (agent-notify2 store get "proc-2" | get -o proc) null)
    ]
    hide-env AGENT_NOTIFY_PID

    let all = ($m ++ $d ++ $e ++ $f ++ $s ++ $s2 ++ $p)
    summarise $all --title "claude client"
}
