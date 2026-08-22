# Small zellij/aerospace helpers shared by the notifier commands.

# The zellij session the (single) Ghostty client is currently viewing, parsed
# from the terminal window title ("<session> | <pane title>"). Returns null if
# it can't be determined. Works without a ZELLIJ env (e.g. from a SketchyBar
# click handler), which is why it reads the window title rather than $ZELLIJ*.
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
