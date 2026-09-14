# zellij as a SESSION-CONTAINER: where an agent lives, and how to get to it.
#
# THE PULL HALF'S OTHER CONTRACT. `mod.nu` is the display (push) and `jump.nu`
# is a command (pull); this is what zellij answers about being the thing agents
# RUN INSIDE (plan.md §4.8, D70). Three questions, none of which a caller can
# answer for itself:
#
#   owns-session         is this session yours?  it has a `zellij` namespace
#   location-label       where does it live?     home
#   focus-session-argv   what would take me      jump argv
#                        there?
#   focus-session        take me there           jump
#
# The last two are one question with a data half in front of it, the same split
# `render-items`/`push-items` make for a display and for the same reason (rule 3
# of `integrations/mod.nu`): a side effect is built as data first, so the suite
# can assert what a jump WOULD run without moving a real screen.
#
# A tmux integration is the same four functions and one more row in
# `integrations/session-containers.nu`. Nothing in `picker/` changes, and
# nothing in the bar does either — which is the whole reason this file exists
# rather than each caller reaching for zellij directly.
#
# IT WAS `locate.nu`, AND IT WAS FILED UNDER `picker/` (D71). Not one of the
# three questions was ever the picker's; what was the picker's is only that it
# asked them first. The second caller — a click on a bar row — is what made that
# visible, because it would have had to reach through the picker to find out
# where an agent lives.
#
# ── THERE WAS A FOURTH, AND IT WAS THE BIG ONE ────────────────────────────────
# `screen` dumped the pane, and the picker's preview was that dump: `zellij
# action dump-screen` reads any pane's live terminal in 12ms, which is truer than
# anything we could record — the `message` is what the agent last SAID, a screen is
# what it is DOING. Step 8 took it out anyway (D58). Truer was not more readable:
# what came back was the bottom of a TUI mid-redraw, half a spinner and a box rule
# cut off at both edges, when the question a picker answers is "which of these
# wants me" and the agent already wrote the answer in a sentence. It also cost a
# subprocess on every heartbeat, and it only ever covered the agents that still
# had a pane — the rest already fell back to the message.
#
# The probes that paid for it are not wasted: `--session` is not optional, because
# PANE IDS ARE PER SESSION (two sessions, both with a pane 0, different contents),
# and `jump.nu` still passes it for exactly that reason. It is written down in
# plan.md §9b.5 for whoever wants a live pane again — as a `watch` command, where
# a whole terminal is the point, rather than as eight lines of a picker.

use jump.nu

export const INFO = {name: "zellij", title: "zellij panes"}

def zellij-of [rec: record]: nothing -> record { $rec.zellij? | default {} }

# A session is ours when it says WHERE it is, completely. A half-known pane — a
# session with no id — is not claimed, so a caller falls back rather than
# guessing at a pane number.
export def owns-session [rec: record]: nothing -> bool {
    let z = zellij-of $rec
    (($z.session? | default "") | is-not-empty) and (($z.pane_id? | default "") | is-not-empty)
}

# One short string for the `where` column: THE SESSION NAME, and nothing else.
#
# It was `<session>/<tab>` until the path arrived. A label is one container's
# contribution to a path now (D77), joined with the ones outside it, so every
# container spending two words where one would do makes the column unreadable by
# the third. The session is the part that tells two agents apart; the tab is
# already visible on the tab bar of the terminal you are about to land in.
#
# The tab is still LEARNED — `discover-own-location` reads it once per session —
# because the zellij DISPLAY needs it to write tab titles. It is simply not what
# a list of agents is for.
export def location-label [rec: record]: nothing -> string {
    $rec.zellij?.session? | default ""
}

# Take me there, and what that would run. One line each, because `jump` already
# knows the three things zellij does that can turn a jump into a silent no-op,
# and knowing them twice would be one place too many.
#
# No return-type signature on `focus-session-argv`: `jump argv` can END in
# `error make` and a def annotated with one cannot (plan.md §10).
export def focus-session-argv [rec: record] { jump argv $rec }

export def focus-session [rec: record]: nothing -> nothing { jump $rec }
