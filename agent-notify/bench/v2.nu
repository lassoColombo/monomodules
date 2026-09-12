# What one v2 hook event actually costs — the number every later step must not
# spoil, measured the same way v1's was (bench/v1.nu) so the two are comparable.
#
# The three cases are the three that matter:
#   re-assert   PostToolUse on an agent already working — the COMMON case by a
#               wide margin, and the one v1 kept a bash script to avoid
#   transition  a real state change, which is what a surface will eventually have
#               to act on
#   end         SessionEnd, which drops a record
#
# The store is a temp directory, so nothing here touches a live agent.

use harness.nu *

const CLIENT = path self ../clients/claude.nu
const TMP = ($nu.temp-dir | path join "agent-notify-bench-v2")

def payload [extra: record = {}]: nothing -> string {
    { session_id: "bench-1", transcript_path: "/tmp/t.jsonl", cwd: "/Users/x/projects/thing"
      permission_mode: "default" } | merge $extra | to json --raw
}

# The invocation as it actually ships: the module IMPORTED via `-c`, not the file
# run as a script. Measuring the script form instead would overstate every number
# here by ~9ms (see the note in clients/claude.nu).
def hook [event: string]: nothing -> list<string> {
    [$NU "-n" "--no-std-lib" "-c" $"use ($CLIENT | to nuon); claude ($event)"]
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    let vars = {XDG_DATA_HOME: $TMP}

    # Put the agent into `working` first, so the re-assert case measures a genuine
    # no-op rather than a create.
    with-env $vars { (payload) | ^$NU ...(hook "UserPromptSubmit" | skip 1) | complete | ignore }

    print ([
        (wall "PostToolUse — re-assert, changed:false" (hook "PostToolUse")
              --vars $vars --stdin (payload {tool_name: "Bash"}) --rounds 25)
        (wall "Stop — a real transition" (hook "Stop")
              --vars $vars --stdin (payload {last_assistant_message: "done"}) --rounds 25
              --prepare {|| with-env $vars { (payload) | ^$NU ...(hook "UserPromptSubmit" | skip 1) | complete | ignore } })
        (wall "SessionEnd — drop" (hook "SessionEnd")
              --vars $vars --stdin (payload {reason: "logout"}) --rounds 15
              --prepare {|| with-env $vars { (payload) | ^$NU ...(hook "SessionStart" | skip 1) | complete | ignore } })
        (wall "an event we do not handle" (hook "PreCompact")
              --vars $vars --stdin (payload) --rounds 15)
    ] | fmt | table --width 100)
}
