# zellij interaction — targeted queries + title writes. No periodic scan: state
# lives in the store (see store.nu); this only reads a single pane's tab context
# on state changes and writes pane/tab titles as projections. Works without a
# $ZELLIJ env — targets each session explicitly with `--session`.

# The zellij session the (single) Ghostty client is currently viewing, parsed
# from the terminal window title ("<session> | <pane title>"). null if unknown.
export def attached-session [] {
    let line = try {
        ^aerospace list-windows --all --format '%{app-name}|%{window-title}'
        | lines | where {|l| $l | str starts-with "Ghostty|" } | get -o 0
    } catch { null }
    if ($line | is-empty) { return null }
    let title = $line | split row "|" | skip 1 | str join "|"
    let s = $title | split row " | " | first | str trim
    if ($s | is-empty) { null } else { $s }
}

# aerospace window-id of the (single) Ghostty window. Focusing it brings the
# terminal forward AND switches to its workspace. null if Ghostty is absent.
export def ghostty-window-id [] {
    try {
        ^aerospace list-windows --all --format '%{window-id}|%{app-name}'
        | lines
        | where {|l| ($l | split row '|' | last | str trim) == "Ghostty" }
        | get -o 0 | split row '|' | first | str trim
    } catch { null }
}

# Every pane of one session (plugin and exited panes included), or null when
# zellij could not be queried. null means "unknown", NEVER "no panes": the
# liveness GC reads an empty list as "they all died" and would wipe the store.
def panes-of [session: string] {
    let r = try { ^zellij --session $session action list-panes -t -j | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) { return null }
    try { $r.stdout | from json } catch { null }
}

# The real (non-plugin, non-exited) panes of one session; null if unknown (see
# panes-of). The single definition of "a real pane" — shared with live.nu.
export def real-panes [session: string] {
    let ps = panes-of $session
    if ($ps == null) { null } else { $ps | where is_plugin == false and exited == false }
}

# One pane's tab context + current title, via a single targeted list-panes.
# → {tab_id, tab_name, tab_position, pane_title} or null if the pane is gone.
export def pane-tab-info [session: string, pane_id: int] {
    let me = real-panes $session | default [] | where id == $pane_id | get -o 0
    if ($me == null) { return null }
    { tab_id: $me.tab_id, tab_name: $me.tab_name, tab_position: $me.tab_position, pane_title: $me.title }
}

# A tab's CURRENT title, read from any pane that belongs to it (every tab has at
# least one, exited ones included). null if the tab — or zellij — is gone. This
# is where a tab's base name actually lives; the store only mirrors it.
export def tab-name [session: string, tab_id: int] {
    let ps = panes-of $session
    if ($ps == null) { return null }
    $ps | where tab_id == $tab_id | get -o 0.tab_name
}

# Set a pane's title (targets the session explicitly so it works from anywhere).
# A blank title DROPS our name instead of writing one, so zellij falls back to
# its own (the running command) — a projection with nothing to say never blanks.
export def rename-pane [session: string, pane_id: int, name: string] {
    let p = ($pane_id | into string)
    if ($name | str trim | is-empty) {
        ^zellij --session $session action undo-rename-pane --pane-id $p | complete | ignore
    } else {
        ^zellij --session $session action rename-pane --pane-id $p $name | complete | ignore
    }
}

# Set a tab's title by id within a session. Blank drops our name (see above):
# zellij restores the layout/default label instead of showing an empty tab.
export def rename-tab [session: string, tab_id: int, name: string] {
    let t = ($tab_id | into string)
    if ($name | str trim | is-empty) {
        ^zellij --session $session action undo-rename-tab --tab-id $t | complete | ignore
    } else {
        ^zellij --session $session action rename-tab --tab-id $t $name | complete | ignore
    }
}

# Open a scratch FLOATING pane running `cmd` (argv, no shell) and hand it the
# focus. Transient by construction: `--close-on-exit` means the pane vanishes the
# instant the command returns, so there is never a dead frame to dismiss. The
# target session is the caller's own, via ambient $ZELLIJ — a no-op elsewhere.
export def float-run [name: string, cmd: list<string>] {
    (^zellij action new-pane --floating --close-on-exit --name $name
        --width "90%" --height "90%" --x "5%" --y 1
        -- ...$cmd) | complete | ignore
}
