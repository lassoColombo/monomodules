# Where an agent lives, what is on its screen, and how to get there.
#
# THE PULL HALF'S OTHER CONTRACT. `mod.nu` is the surface (push) and `jump.nu` is
# a command (pull); this is what the PICKER needs from a tool, and it is four
# questions the picker cannot answer for itself:
#
#   claims   is this record yours?          it has a `zellij` namespace
#   place    where does it live?            home/root
#   screen   what is on its screen?         dump-screen
#   go       take me there                  jump
#
# A tmux integration is the same four functions and one more row in
# `picker/locators.nu`. Nothing in `picker/` changes. That is the whole reason
# this file exists rather than the picker calling zellij directly.
#
# THE PREVIEW IS THE AGENT'S REAL TERMINAL, not its stored message. `dump-screen`
# reads any pane's live screen for 12ms, which makes the preview truer than
# anything we could keep: the store's `message` is what the agent last SAID, the
# screen is what it is DOING. It also deletes markdown rendering from this module
# outright.
#
# ── --session IS NOT OPTIONAL ────────────────────────────────────────────────
# PANE IDS ARE PER SESSION. Probed: two sessions, both with a pane 0, different
# contents. `zellij action dump-screen --pane-id terminal_0` with no `--session`
# reads whichever session this process is attached to — so an agent living
# ANYWHERE ELSE would show a stranger's terminal, silently, with no error at all.
# `jump.nu` has always passed `--session`; this must too, and for the same reason.
#
# ── WHEN THERE IS NOTHING TO SHOW ────────────────────────────────────────────
# `screen` returns an EMPTY LIST rather than an apology. Three ways to get there,
# and the picker turns all of them into the same fallback — the stored message:
#
#   the pane is gone      the agent died and the clock has not pruned it yet
#   the pane is ours      `browse` runs in place (D52), so the selected record
#                         can be THIS pane, and dumping it would show the picker
#                         looking at itself
#   the dump is blank     a pane that has not painted yet

use ../../core/config.nu
use program.nu
use jump.nu

export const INFO = {name: "zellij", title: "zellij panes"}

# The same three lines as `jump.nu`'s, and duplicated for the same reason the
# surfaces duplicate their glyphs: `program.nu` must stay a leaf, because the HOT
# half imports it and `core/config.nu` is already in the hook's cone (§10, D29).
def binary []: nothing -> string {
    let given = config section (config load) "zellij" "commands"
    program resolve ($given.binary? | default "")
}

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

# See note 3 in jump.nu: a pane is `7` in the store and `terminal_7` on the wire.
def pane-ref [id: string]: nothing -> string {
    if ($id | str starts-with "terminal_") { $id } else { $"terminal_($id)" }
}

# The BOTTOM of the pane, which is the part that is current. Trailing blank lines
# come off first — a dump is always full height — but interior ones stay, because
# removing them would compress the screen and misalign what is left.
def tail-of [text: string, lines: int]: nothing -> list<string> {
    let all = $text | lines
    let body = $all | reverse | skip while {|l| ($l | str trim) | is-empty } | reverse
    if ($body | is-empty) { return [] }
    $body | last ([$lines ($body | length)] | math min)
}

# The agent's live screen, at most `lines` of it. Empty when there is nothing to
# show — see the header.
export def screen [rec: record, lines: int]: nothing -> list<string> {
    if not (claims $rec) { return [] }
    if $lines < 1 { return [] }
    let z = zellij-of $rec
    let pane = pane-ref ($z.pane_id | into string)

    # Looking at ourselves. `browse` runs in place, so this is not hypothetical.
    let here = $env.ZELLIJ_PANE_ID? | default ""
    let mine = ($z.session == ($env.ZELLIJ_SESSION_NAME? | default "")) and ($pane == (pane-ref $here))
    if ($here | is-not-empty) and $mine { return [] }

    let bin = try { binary } catch { "" }
    if ($bin | is-empty) { return [] }
    let r = try {
        ^$bin --session $z.session action dump-screen --pane-id $pane | complete
    } catch { null }
    # zellij exits 0 whether or not it worked (jump.nu, note 1), so the exit code
    # says nothing — an empty stdout is the only answer that means "nothing here".
    if ($r == null) or (($r.stdout | str trim) | is-empty) { return [] }
    tail-of $r.stdout $lines
}

# Take me there. One line, because `jump` already knows the three things zellij
# does that can turn a jump into a silent no-op, and knowing them twice would be
# one place too many.
export def go [rec: record]: nothing -> nothing {
    jump ($rec.id? | default "")
}
