# What the agent under the cursor last said, cut to fit the pane.
#
# PURE, which it could not be before. Until step 8 the preview was the agent's
# LIVE TERMINAL — `zellij action dump-screen`, 12ms of subprocess per frame — so
# it had to live in `mod.nu` beside the other calls that touch the world, and it
# was the one part of the frame the suite could not assert. It is now a function
# of the record, so it moved out here and got its own assertions.
#
# ── WHY THE STORED MESSAGE BEAT THE REAL SCREEN (reverses D57, see D58) ──────
# A pane dump is TRUER — it is what the agent is doing, not what it last said —
# and it was still the wrong thing to show. Three reasons, in the order they
# matter:
#
#   IT IS NOT READABLE. A dump is the bottom of a terminal: a half-drawn spinner,
#   a box-drawing frame cut off at both edges, whatever the agent's own TUI was
#   painting mid-redraw. The question a picker answers is "which of these wants
#   me", and the sentence the agent wrote is the answer to it. The screen is
#   something you have to decode first.
#
#   IT COSTS A SUBPROCESS PER FRAME. The heartbeat redraws every 2 seconds, so a
#   picker sitting open spawned a zellij client forever. The store read it now
#   replaces is 0.33ms and was already happening.
#
#   IT WAS ONLY EVER HALF THE CASES. An agent with no pane — dead, remote, or
#   `browse` looking at its own pane — already fell back to exactly this. Two
#   codepaths for one pane of text, and the fallback was the one that worked
#   everywhere.
#
# What it costs: staleness. A message is what the agent said when it last
# stopped, so a long turn shows the previous answer. That is what the STATE
# column is for — `working` beside a stale message reads correctly.
#
# ── AND WHY IT IS THE BAR'S RENDERING ────────────────────────────────────────
# `core/markdown.nu`, the same flattener the drawer uses. The bar reached the
# right answer first and there is no second answer to have: a message is
# markdown, and neither a label nor a terminal rectangle can render it. One
# reader means one place to fix a fence that comes out wrong.

use ../core/markdown.nu

# An agent that has said nothing. The bar's word for it, because it is the same
# preview — and a dash reads as "nothing here" where a sentence would read as
# something the agent said.
const NOTHING = {k: "text", t: "—"}

# The selected row's message, flattened and cut to the pane. `row` is null when
# the list is empty, which is an ordinary state for a picker to be in.
#
# CUT FROM THE TOP, always. The live screen was cut from the BOTTOM — a terminal's
# last line is its current one — and losing that asymmetry is a simplification,
# not a loss: a message's first line is its point, and everything after it is
# elaboration.
# ── SCROLLING, AND WHY THIS IS THE ONLY PLACE THAT CAN CLAMP IT (D63) ────────
# `at` is the message's first visible row — `top` for the other rectangle on the
# screen. A key can only ever say "further down": HOW FAR DOWN A MESSAGE GOES IS
# NOT KNOWN UNTIL IT IS REACHED, because `markdown plain` is given a line budget
# and stops there (D61), so nothing renders the whole of a message just to count
# it. Asking for one row more than the pane holds is what makes the end
# detectable: getting FEWER back than were asked for is the proof that there is
# no more, and it is the only moment a last page can be worked out.
#
# So the offset is CORRECTED here and handed back with the rows, the way `rows
# settle` corrects the list's. `mod.nu` writes it into the view, and holding
# ctrl-d at the bottom of a message stops rather than running up a number that
# then needs undoing.
#
# ROWS, NOT STRINGS: `{k, t}`, because what a row IS is what `frame.nu` colours
# it by. Nothing is painted here — this file is a function of the record and
# knows nothing about a terminal (D62).
export def of [row: any, height: int, width: int, at: int = 0]: nothing -> record {
    if ($row == null) or ($height < 1) or ($width < 1) { return {at: 0, rows: []} }
    let said = $row.rec?.message? | default ""
    # Floored ONCE, here, so nothing below this line can be handed a negative
    # index — `skip` refuses one, and the picker would go down with it.
    let from = [0 $at] | math max
    let want = $from + $height + 1
    let all = markdown plain $said $width $want
    # Fewer rows than were asked for means the message ended inside them, which
    # is the only case where the last page is knowable.
    let last = if (($all | length) < $want) { [0 (($all | length) - $height)] | math max } else { $from }
    let now = [$from $last] | math min
    let body = markdown lay-out ($all | skip $now) $width $height
    if ($body | is-empty) { return {at: 0, rows: [$NOTHING]} }
    {at: $now, rows: $body}
}
