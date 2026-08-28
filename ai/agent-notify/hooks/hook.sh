#!/usr/bin/env bash
# Claude Code hook glue for agent-notify — the one entry point every hook in
# ~/.claude/settings.json calls:
#
#   hook.sh session-start     SessionStart
#   hook.sh working           UserPromptSubmit, PostToolUse
#   hook.sh awaiting          Stop
#   hook.sh needs-attention   Notification
#   hook.sh clear             SessionEnd
#
# It does two things: hand the hook's JSON payload to the matching verb, and
# poke SketchyBar so the bar repaints at once instead of waiting for its slow
# janitor pass. Everything else is the module's job.
#
# WHY A SCRIPT AND NOT SIX ONE-LINERS: PostToolUse fires on EVERY tool call, of
# every agent, and its verb is idempotent — after the first one of a turn the
# record already says "working" and the whole chain (nu startup + module parse,
# a store read, a SketchyBar trigger, and the render nu that trigger spawns) is
# ~72ms of CPU spent to change nothing. A shell can answer "am I already
# working?" from the record itself, and the answer is a substring test.
#
# So the fast path below is deliberately fork-free — `$(<file)` is optimised in
# bash, `case` is a builtin — and costs ~2ms. It reads the store's on-disk shape
# (lib/paths.nu for the directory, lib/store.nu for the file name and the JSON),
# which is duplication, and the reason it is worth it is that thirty-five times
# out of thirty-six there is nothing for the module to say. A miss is free: an
# unreadable or unrecognised record just falls through to the real verb, which
# recomputes everything from scratch.
#
# The one thing the fast path must still do is drain the payload — Claude Code
# writes it to our stdin, and a payload past the pipe buffer would block a
# reader that has already gone. `exec cat` replaces this shell rather than
# forking a second process for it.
export PATH="/opt/homebrew/bin:$PATH"

VERB="${1:?usage: hook.sh <session-start|working|awaiting|needs-attention|clear>}"
SB=/opt/homebrew/bin/sketchybar
NU=/opt/homebrew/bin/nu

# Every verb is a no-op without a pane to label (mod.nu's `my-ids`), so an agent
# outside zellij can stop here — before the nu spawn AND before the poke, since
# with no record to change a repaint would find the model identical anyway.
[ -n "${ZELLIJ_PANE_ID:-}" ] && [ -n "${ZELLIJ_SESSION_NAME:-}" ] || exit 0

if [ "$VERB" = working ]; then
    REC="${XDG_DATA_HOME:-$HOME/.local/share}/agent-notify/${ZELLIJ_SESSION_NAME//\//_}.$ZELLIJ_PANE_ID.json"
    if [ -e "$REC" ]; then
        case "$(<"$REC")" in
            *'"state": "working"'*|*'"state":"working"'*) exec cat >/dev/null ;;
        esac
    fi
fi

# The repo this module lives in, derived rather than configured: this script is
# <lib>/ai/agent-notify/hooks/hook.sh, so three levels up is what `use ai`
# resolves against. Worked out here and not at the top because it is the one
# thing in this script that costs a fork, and the fast path above never needs it.
SELF_DIR="${BASH_SOURCE[0]%/*}"
[ "$SELF_DIR" = "${BASH_SOURCE[0]}" ] && SELF_DIR=.
export NU_LIB_DIRS="$(cd "$SELF_DIR/../../.." && pwd)"

"$NU" -n -c "use ai; try { open --raw /dev/stdin | from json | ai agent-notify $VERB Claude }"

# `alert` for the two states that want the drawer to flash (render/mod.nu
# re-checks the stored state, so a filtered Notification stays a silent
# repaint); a plain repaint for the rest.
case "$VERB" in
    awaiting|needs-attention)
        "$SB" --trigger agent_notify_alert STATE="$VERB" \
              SESSION="$ZELLIJ_SESSION_NAME" PANE="$ZELLIJ_PANE_ID" 2>/dev/null ;;
    *) "$SB" --trigger agent_notify_update 2>/dev/null ;;
esac
exit 0
