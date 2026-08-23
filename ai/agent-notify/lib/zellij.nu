# zellij interaction — the live-pane topology plus title-writing verbs.
#
# The pane titles ARE the single source of truth for agent state: they die with
# the pane, so a killed agent can't leave a stale record behind. `scan` reads
# every live session's real panes; both surfaces (tab titles, the SketchyBar
# popup) are pure functions of it. Works without a $ZELLIJ env — targets each
# session explicitly with `--session`, so it runs from a bar plugin all the same.

# The zellij session the (single) Ghostty client is currently viewing, parsed
# from the terminal window title ("<session> | <pane title>"). Returns null if
# it can't be determined. Works without a ZELLIJ env (e.g. from a SketchyBar
# click handler), which is why it reads the window title rather than $ZELLIJ*.
export def attached-session [] {
    let line = try {
        ^aerospace list-windows --all --format '%{app-name}|%{window-title}'
        | lines | where {|l| $l | str starts-with "Ghostty|" } | get -o 0
    }
    if ($line | is-empty) { return null }
    let title = $line | split row "|" | skip 1 | str join "|"
    let s = $title | split row " | " | first | str trim
    if ($s | is-empty) { null } else { $s }
}

# aerospace window-id of the (single) Ghostty window. Focusing it brings the
# terminal forward AND switches to its workspace — works from any workspace,
# including an empty one, where `open -a` does nothing. null if Ghostty is absent.
export def ghostty-window-id [] {
    try {
        ^aerospace list-windows --all --format '%{window-id}|%{app-name}'
        | lines
        | where {|l| ($l | split row '|' | last | str trim) == "Ghostty" }
        | get -o 0 | split row '|' | first | str trim
    }
}

# Names of sessions that are actually running (not EXITED / resurrectable).
export def live-sessions [] {
    try {
        ^zellij list-sessions -n
        | lines
        | where {|l| not ($l | str contains "EXITED") }
        | each {|l| $l | str trim | split row ' ' | first }
        | where {|s| $s != "" }
    } catch { [] }
}

# Real terminal panes of one session, tagged with the session name. Plugin panes
# (share ids with terminals) and exited panes are dropped. [] if the session is gone.
export def session-panes [session: string] {
    try {
        ^zellij --session $session action list-panes -t -j
        | from json
        | where is_plugin == false and exited == false
        | insert session $session
        | select session id title tab_id tab_position tab_name
    } catch { [] }
}

# Every live agent-capable pane across every live session — the unified source.
export def scan [] {
    live-sessions | each {|s| session-panes $s } | flatten
}

# Set a pane's title (targets the session explicitly so it works from anywhere).
export def rename-pane [session: string, pane_id: int, name: string] {
    ^zellij --session $session action rename-pane --pane-id ($pane_id | into string) $name | complete | ignore
}

# Set a tab's title by id within a session.
export def rename-tab [session: string, tab_id: int, name: string] {
    ^zellij --session $session action rename-tab --tab-id ($tab_id | into string) $name | complete | ignore
}

# Nudge the SketchyBar popup to re-read the live panes. No-op if not installed.
export def poke [] {
    try { ^sketchybar --trigger agent_notify_update | complete | ignore }
}
