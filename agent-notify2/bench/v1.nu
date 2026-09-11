# Case group 4 — THE BASELINE: what v1 actually costs per hook event, end to end.
# This is the number v2 is judged against, so it is measured rather than summed
# from the parts wherever that can be done safely.
#
# SAFETY / FIDELITY notes, because both matter here:
#   - XDG_DATA_HOME points at a temp store, so the live record is never touched.
#   - ZELLIJ_PANE_ID is 99999: `my-ids` is satisfied (so the verb runs in full),
#     `pane-tab-info` finds no such pane (so the TAB projection is skipped — real
#     events would sometimes pay one more ~11ms rename), and `rename-pane` still
#     makes its full round trip against a pane that does not exist. So these
#     numbers are a slight UNDER-count of a real event, never an over-count.
#   - the fast-path case seeds a record that already says "working", which is the
#     condition hook.sh's shortcut tests for. It needs a payload on stdin: on a
#     hit the script `exec cat`s the body to unblock the writer.
#   - `render` runs against the REAL store and REAL cache on purpose: the model
#     comes back unchanged, so it sends sketchybar nothing and disturbs nothing,
#     which is exactly the redundant-poke case worth pricing.

use harness.nu *

const REPO = path self ../..
const HOOK = path self ../../ai/agent-notify/hooks/hook.sh
const TMP = ($nu.temp-dir | path join "agent-notify2-bench-v1store")

# A realistic PostToolUse body.
def payload [] {
    { session_id: "bench", transcript_path: "/tmp/nope.jsonl", cwd: $REPO
      hook_event_name: "PostToolUse", tool_name: "Bash"
      tool_input: {command: "echo hi", description: "realistic-ish"}
      tool_response: {stdout: "ok", stderr: "", interrupted: false} } | to json --raw
}

# A Stop body whose message is markdown — the case that pays for pandoc.
def stop-md [] {
    let msg = "Here's what I found:\n\n- **first** point with `code`\n- second point\n\n```nu\nlet x = 1\n```\n\nDone."
    { session_id: "bench", transcript_path: "/tmp/nope.jsonl", cwd: $REPO
      hook_event_name: "Stop", last_assistant_message: $msg } | to json --raw
}

# A Stop body whose message is one plain line — `plain-already` short-circuits,
# so no subprocess. The difference between this and the case above IS pandoc.
def stop-plain [] {
    { session_id: "bench", transcript_path: "/tmp/nope.jsonl", cwd: $REPO
      hook_event_name: "Stop", last_assistant_message: "All set, the tests pass." } | to json --raw
}

def vars [] {
    { XDG_DATA_HOME: $TMP
      ZELLIJ_SESSION_NAME: ($env.ZELLIJ_SESSION_NAME? | default "home")
      ZELLIJ_PANE_ID: "99999" }
}

def seed-working [] {
    let dir = [$TMP "agent-notify"] | path join
    if not ($dir | path exists) { mkdir $dir }
    let sess = $env.ZELLIJ_SESSION_NAME? | default "home"
    { session: $sess, pane_id: 99999, agent: "Claude", state: "working"
      pane_name: "bench", pane_locked: true, preview: "", preview_md: "" }
    | to json | save --force ([$dir $"($sess).99999.json"] | path join)
}

# The verb on its own, without hook.sh's gate — this is what the MISS path runs.
def verb [v: string] {
    [$NU "-n" "-I" $REPO "-c" $"use ai; open --raw /dev/stdin | from json | ai agent-notify ($v) Claude"]
}

export def main [] {
    seed-working

    print "── v1 per-event cost (ms) ───────────────────────────────────────────"
    print ([
        (wall "hook.sh working — FAST PATH (bash only)" ["/bin/bash" $HOOK "working"]
            --vars (vars) --stdin (payload) --rounds 25)
        (wall "verb working    — the miss path" (verb "working")
            --vars (vars) --stdin (payload) --rounds 20)
        (wall "verb awaiting   — plain message (no pandoc)" (verb "awaiting")
            --vars (vars) --stdin (stop-plain) --rounds 20)
        (wall "verb awaiting   — markdown (pandoc)" (verb "awaiting")
            --vars (vars) --stdin (stop-md) --rounds 20)
    ] | fmt | table --width 100)

    print ""
    print "── the bar side (ms) ────────────────────────────────────────────────"
    print ([
        (wall "render, model UNCHANGED (a wasted poke)" [$NU "-n" "-I" $REPO "-c" "use ai; ai agent-notify render"] --rounds 20)
    ] | fmt | table --width 100)
}
