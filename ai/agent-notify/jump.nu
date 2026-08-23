# `ai agent-notify jump <session> <pane_id>` — bring the terminal forward and
# switch its client to <session>, focusing the exact agent PANE (not just the
# tab). Safe to call from outside zellij (e.g. a SketchyBar notification click),
# since it derives the currently-attached session from the window title rather
# than $ZELLIJ*.

use lib/zellij.nu *

export def main [session: string, pane_id: int] {
    # Bring Ghostty forward from ANY aerospace workspace (open -a is unreliable
    # from an empty one). Fall back to launching it if it isn't running.
    let gid = ghostty-window-id
    if ($gid | is-empty) { ^open -a Ghostty } else { ^aerospace focus --window-id $gid }

    let attached = attached-session
    let pid = $"terminal_($pane_id)"
    if $attached == null {
        # No detectable client; best-effort switch using ambient context.
        try { ^zellij action switch-session $session --pane-id $pid }
        return
    }
    if $attached == $session {
        ^zellij --session $attached action focus-pane-id $pid
    } else {
        ^zellij --session $attached action switch-session $session --pane-id $pid
    }
}
