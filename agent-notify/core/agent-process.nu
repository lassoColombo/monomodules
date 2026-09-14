# "Is that agent still running?" — the only question with an honest answer.
#
# An agent is a process. If its process is gone, the agent is gone. Every other
# signal we considered is a proxy for that fact, and every proxy is wrong in
# some case: a zellij pane outlives the process it held, a transcript file
# outlives the session that wrote it, and a quiet record means "idle" as often
# as "dead".
#
# Nobody hands us the pid, so we find it: a hook is STARTED BY the agent, which
# makes it a descendant, and a descendant can always ask who started it.
#
#   83758  nu                         ← the hook
#   83572  /bin/zsh                   ← the shell Claude ran the command with
#   3234   /opt/homebrew/bin/claude   ← the agent
#   2837   nu                         ← the pane's shell
#   907    /opt/homebrew/bin/zellij
#
# We cannot take the parent (that shell dies the moment the hook returns) and we
# cannot count steps (an agent that runs the command directly has one fewer). So
# we climb until we meet the name the AGENT declares — `agents/claude.nu` says
# `process: "claude"`, which is where agent-specific knowledge already lives.
# `$env.AGENT_NOTIFY_PID` short-circuits all of it, the same escape hatch
# `AGENT_NOTIFY_ID` gives for current-session.
#
# ONCE PER SESSION, at SessionStart. A pid does not change, so there is nothing
# to repeat, and the rest of the hook path is untouched.
#
# WHY THE START TIME IS STORED WITH IT: pids are recycled. Store only the number
# and in an hour some unrelated program is 3234, we ask "is 3234 running?", hear
# "yes", and keep a dead agent forever in the belief that a stranger is our
# agent. A pid AND the second it started cannot be confused for anything else.

const MAX_DEPTH = 8

# One process, as `ps` sees it: who started it, when it started, what it is.
# `lstart` is five whitespace-separated tokens ("Fri Sep 11 18:59:20 2026"), so
# the command is whatever follows them — which survives a path containing
# spaces.
def info-of [pid: int]: nothing -> any {
    let r = try { ^ps -o ppid=,lstart=,comm= -p ($pid | into string) | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) { return null }
    let f = $r.stdout | str trim | split row --regex '\s+'
    if ($f | length) < 7 { return null }
    { ppid: ($f.0 | into int)
      started: ($f | skip 1 | first 5 | str join " ")
      comm: ($f | skip 6 | str join " ") }
}

# The agent's process, as {pid, started} — or null when we cannot tell, which
# the callers must read as "no proof" and never as "dead".
export def find-mine [process: string]: nothing -> any {
    let told = $env.AGENT_NOTIFY_PID? | default ""
    if ($told | is-not-empty) {
        let pid = try { $told | into int } catch { 0 }
        let me = if $pid > 0 { info-of $pid } else { null }
        return (if ($me == null) { null } else { {pid: $pid, started: $me.started} })
    }
    if ($process | is-empty) { return null }

    mut pid = $nu.pid
    for _ in 1..$MAX_DEPTH {
        let cur = info-of $pid
        if $cur == null { return null }
        if (($cur.comm | path basename) == $process) { return {pid: $pid, started: $cur.started} }
        if $cur.ppid <= 1 { return null }
        $pid = $cur.ppid
    }
    null
}

# Which of these processes are still running, as a list of pids. Only a pid
# whose START TIME still matches counts — a recycled number is a different
# process.
#
# Returns NULL when `ps` could not answer at all, which is different from an
# empty list: empty means "none of them are running", null means "do not act on
# this". `ps` distinguishes them itself — it exits 1 with nothing on stderr when
# every pid is simply absent, and complains on stderr when the question was
# malformed.
export def still-running [processes: list<record>]: nothing -> any {
    let want = $processes | where {|p| ($p.pid? | default 0) > 0 }
    if ($want | is-empty) { return [] }

    let arg = $want | get pid | uniq | each {|p| $p | into string } | str join ","
    let r = try { ^ps -o pid=,lstart= -p $arg | complete } catch { null }
    if $r == null { return null }
    if ($r.exit_code != 0) and (($r.stderr | str trim) | is-not-empty) { return null }

    let running = $r.stdout | lines | each {|l|
        let f = $l | str trim | split row --regex '\s+'
        if ($f | length) < 6 { null } else { {pid: ($f.0 | into int), started: ($f | skip 1 | str join " ")} }
    } | compact

    $want
    | where {|p| $running | any {|n| ($n.pid == $p.pid) and ($n.started == $p.started) } }
    | get pid
    | uniq
}
