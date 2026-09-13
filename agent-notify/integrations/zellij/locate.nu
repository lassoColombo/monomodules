# Where an agent lives, and how to get there.
#
# THE PULL HALF'S OTHER CONTRACT. `mod.nu` is the surface (push) and `jump.nu` is
# a command (pull); this is what the PICKER needs from a tool, and it is three
# questions the picker cannot answer for itself:
#
#   claims   is this record yours?          it has a `zellij` namespace
#   place    where does it live?            home/root
#   go       take me there                  jump
#
# A tmux integration is the same three functions and one more row in
# `picker/locators.nu`. Nothing in `picker/` changes. That is the whole reason
# this file exists rather than the picker calling zellij directly.
#
# ── THERE WAS A FOURTH, AND IT WAS THE BIG ONE ───────────────────────────────
# `screen` dumped the pane, and the picker's preview was that dump: `zellij
# action dump-screen` reads any pane's live terminal in 12ms, which is truer than
# anything we could store — the `message` is what the agent last SAID, a screen is
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

# A record is ours when it says WHERE it is, completely. A half-known pane — a
# session with no id — is not claimed, so the picker falls back rather than
# guessing at a pane number.
export def claims [rec: record]: nothing -> bool {
    let z = zellij-of $rec
    (($z.session? | default "") | is-not-empty) and (($z.pane_id? | default "") | is-not-empty)
}

# One short string for the `where` column. The tab's own name when we learned it
# (`observe` does, once per session), its id when we did not.
export def place [rec: record]: nothing -> string {
    let z = zellij-of $rec
    let session = $z.session? | default ""
    if ($session | is-empty) { return "" }
    let tab = $z.tab_base? | default ""
    let label = if ($tab | is-not-empty) { $tab } else { $z.tab_id? | default "" | into string }
    if ($label | is-empty) { $session } else { $"($session)/($label)" }
}

# Take me there. One line, because `jump` already knows the three things zellij
# does that can turn a jump into a silent no-op, and knowing them twice would be
# one place too many.
export def go [rec: record]: nothing -> nothing {
    jump ($rec.id? | default "")
}
