# Item names, the fixed pool, and the shell the bar runs on its own.
#
# Everything here is PURE: functions that return argument lists, never a
# subprocess. `mod.nu` sends what they build, and the test suite reads it with no
# bar installed at all.
#
# THE GENERATED SHELL is the part worth understanding. A drawer opens on hover
# and a row's preview fills on hover, and SketchyBar has only one way to react to
# a mouse: run an item's `script`. v1 pointed those scripts at files in
# ~/.config/sketchybar/plugins, and the row's one started a whole nushell — read
# the store, wrap the text, send it — about 47ms for every row the pointer
# brushed past.
#
# Here the script IS the answer. A `script` is handed to a shell (probed: the
# daemon expands $SENDER and honours quoting), so we write the sketchybar command
# that the hover should run and store it on the item. Two consequences:
#
#   nothing of ours lives in the bar's config directory — still true, which is
#   the whole v2 bargain; and
#
#   a hover costs one `sh` plus one client, ~7ms, with no store read and nothing
#   that can go stale, because the text was written by the same paint that wrote
#   the row.
#
# The price is that a preview's text is baked into a shell command, so it must be
# safe to single-quote. `text.nu`'s `quotable` is the whole of that: a literal
# `'` becomes `’` and control characters become spaces. Probed on the real
# daemon — inside single quotes `$HOME` and backticks stay literal.
#
# EVERY SCRIPT GUARDS ON $SENDER. An item's script also runs on a forced
# `--update`, which SketchyBar sends at bar load; without the guard the bar would
# open a drawer nobody hovered.

# The three states worth a counter, in the order they are added to the bar. Idle
# is not one: an agent with nothing to say does not deserve a number.
export const COUNTED = ["working" "awaiting" "needs-attention"]

# Escapes, not literal characters — Private Use Area glyphs do not survive
# ordinary tooling (plan.md §10). The same three shapes the zellij titles use,
# deliberately: one vocabulary, learned once.
export const GLYPHS = {
    working: "\u{f021}"           # circular arrows — turning
    awaiting: "\u{f075}"          # speech bubble — talking to you
    needs-attention: "\u{f071}"   # warning triangle — stuck
}

# ── names ────────────────────────────────────────────────────────────────────
# "needs-attention" is not a legal item name, and a name is the only handle the
# bar gives us, so the suffix is fixed here and nowhere else.

def suffix [state: string]: nothing -> string {
    if $state == "needs-attention" { "attention" } else { $state }
}

export def chip [s: record, state: string]: nothing -> string { $"($s.prefix)(suffix $state)" }
export def head [s: record, state: string]: nothing -> string { $"(chip $s $state).head" }
export def row-name [s: record, state: string, i: int]: nothing -> string { $"(chip $s $state).row.($i)" }
export def pv-name [s: record, state: string, i: int]: nothing -> string { $"(chip $s $state).pv.($i)" }
export def group [s: record]: nothing -> string { $"($s.prefix)group" }
export def sentinel [s: record]: nothing -> string { $"($s.prefix)exit" }

# Same hue, less alpha: a counter at zero stays recognisable by colour instead of
# going grey, so the three icons read at a glance the way the wifi and battery
# widgets do.
export def tint [color: string, alpha: string]: nothing -> string {
    $"0x($alpha)($color | str substring 4..)"
}

# ── the shell a hover runs ───────────────────────────────────────────────────

const GUARD = "[ \"$SENDER\" = mouse.entered ] || exit 0; exec "

# Shut every drawer. Static — it depends on nothing that a paint can change —
# so it is written once, at install, and never rewritten.
export def close-args [s: record]: nothing -> list<string> {
    $COUNTED | each {|st| ["--set" (chip $s $st) "popup.drawing=off"] } | flatten
}

def close-shell [s: record]: nothing -> string {
    $"($s.binary) (close-args $s | str join ' ')"
}

# Hovering a chip opens ITS drawer and shuts the other two, because sliding along
# the bar must not leave a trail of open popups behind. It also blanks its own
# preview footer, so a drawer never reappears showing the last row you read.
#
# An EMPTY drawer opens NOTHING — popping "All clear" at a pointer merely
# crossing the bar is noise — but it still CLOSES the others: moving sideways off
# a counter means you are done with the one you left. v1 needed a flag file on
# disk to know which counters were empty; here the count is already in hand, and
# the script is rewritten only when it crosses zero.
export def open-shell [s: record, state: string, n: int]: nothing -> string {
    if $n == 0 { return ($GUARD + (close-shell $s)) }
    let others = $COUNTED | where {|st| $st != $state }
        | each {|st| ["--set" (chip $s $st) "popup.drawing=off"] } | flatten
    let blank = 0..<$s.preview_lines | each {|i| ["--set" (pv-name $s $state $i) "drawing=off"] } | flatten
    let args = ["--set" (chip $s $state) "popup.drawing=on"] ++ $others ++ $blank
    $GUARD + $"($s.binary) ($args | str join ' ')"
}

# One row's preview, as the command that will show it. Called at PAINT time with
# the lines already wrapped, so the hover itself does no thinking.
export def hover-shell [s: record, state: string, lines: list<string>]: nothing -> string {
    let args = 0..<$s.preview_lines | each {|i|
        let l = $lines | get -o $i
        if $l == null {
            ["--set" (pv-name $s $state $i) "drawing=off"]
        } else {
            ["--set" (pv-name $s $state $i) $"'label=($l)'" "drawing=on"]
        }
    } | flatten
    $GUARD + $"($s.binary) ($args | str join ' ')"
}

# ── what a paint writes ──────────────────────────────────────────────────────

# A drawer's size changed: the chip's number, its header, and — since an empty
# drawer opens nothing — the script behind it.
export def counter-args [s: record, state: string, n: int]: nothing -> list<string> {
    let item = chip $s $state
    let hue = $s.colors | get $state
    let label = if $n == 0 { "  All clear"
        } else if $n > $s.rows { $"  ($n) active · ($s.rows) shown"
        } else { $"  ($n) active" }
    [ "--set" $item
      $"icon.color=(if $n > 0 { $hue } else { (tint $hue '66') })"
      $"label=($n)"
      $"label.color=(if $n > 0 { $hue } else { $s.colors.dim })"
      $"script=(open-shell $s $state $n)"
      "--set" (head $s $state)
      $"icon=(if $n == 0 { '✓' } else { '' })"
      $"icon.color=(if $n == 0 { $s.colors.working } else { $s.colors.dim })"
      $"label=($label)" ]
}

# One agent's row: what it says, and what hovering it shows.
export def row-args [s: record, state: string, i: int, v: record]: nothing -> list<string> {
    [ "--set" (row-name $s $state $i)
      $"label=($v.label)"
      "drawing=on"
      $"script=(hover-shell $s $state $v.lines)" ]
}

# A row with no agent behind it any more. The script goes too, so a 1KB preview
# of an agent that is gone is not left sitting on the item.
export def row-off-args [s: record, state: string, i: int]: nothing -> list<string> {
    ["--set" (row-name $s $state $i) "drawing=off" "script="]
}

# ── the pool, created once ───────────────────────────────────────────────────
# WHAT THIS COSTS, measured on the real bar, because the numbers chose the shape:
#
#   --add 70 items in ONE message    40.8ms   ← once, at bar load
#   --set 70 labels in ONE message   18.6ms   ← a paint touches one or two
#
# So the pool is built in a single message at install and never added to or
# removed from again. v1 learned the other way, rebuilding ~43 items per paint
# and pinning the daemon near 40% CPU — which is what used to make bar clicks lag.
#
# NO TIMER HERE. An earlier version hung a hidden `update_freq=30` item off this
# pool to prune dead agents and repaint. It worked, and it was still wrong: it
# made a core guarantee depend on one optional surface being installed. The clock
# is its own thing now (core/clock.nu), and this file is only a surface again.
export def pool-args [s: record]: nothing -> list<string> {
    mut args = []
    for state in $COUNTED {
        let item = chip $s $state
        let hue = $s.colors | get $state
        # Idempotent: a re-run wipes this drawer's children first, so changing
        # `rows` in the config cannot leave orphans behind. The regex needs the
        # dot, so the chip itself survives and keeps its place on the bar.
        $args = $args ++ ["--remove" $"/($item)\\..*/"]
        $args = $args ++ [
            "--add" "item" $item $s.position
            "--set" $item
            $"icon=($GLYPHS | get $state)"
            $"icon.font=($s.font):Bold:15.0"
            $"icon.color=(tint $hue '66')"
            "label=0"
            $"label.font=($s.font):Semibold:13.0"
            $"label.color=($s.colors.dim)"
            # popup.align=left so a drawer opens rightward; align=right ran it
            # off the screen edge.
            #
            # popup.height is THE VERTICAL SPACING BETWEEN ROWS, and left alone
            # it is the BAR's height — 34px around a 12pt line, which is why an
            # untouched drawer is nine tenths air. A row's own background.height
            # cannot correct it: that sizes the pill, not the slot.
            $"popup.height=($s.line_height)"
            "popup.align=left" "popup.background.drawing=on"
            $"popup.background.color=($s.colors.popup)"
            "popup.background.corner_radius=10" "popup.background.border_width=1"
            $"popup.background.border_color=($s.colors.border)"
            $"script=(open-shell $s $state 0)"
            $"click_script=(close-shell $s)"
            "--subscribe" $item "mouse.entered"
        ]
        $args = $args ++ [
            "--add" "item" (head $s $state) $"popup.($item)"
            "--set" (head $s $state)
            $"icon.font=($s.font):Bold:11.0"
            $"label.font=($s.font):Bold:11.0"
            $"label.color=($s.colors.dim)"
            $"icon.color=($s.colors.dim)"
            "label=  All clear" "icon=✓"
            "icon.padding_left=14" "label.padding_right=14"
            "background.drawing=off" "y_offset=1"
        ]
        # THE GAP: a row has no `click_script`, so clicking an agent does nothing.
        # Not an oversight — see plan.md §9b.1. Everything the click needs is
        # already here (the row knows its agent at paint time, and D44 says bake
        # the answer in as a shell line rather than spawn one of ours). What is
        # missing is the RAISE: a bar click comes from a desktop, so the
        # terminal's WINDOW has to come forward before a pane can be focused, and
        # that is a window manager's job. D50 says this module names none.
        for i in 0..<$s.rows {
            let n = row-name $s $state $i
            $args = $args ++ [
                "--add" "item" $n $"popup.($item)"
                "--set" $n "drawing=off"
                "background.drawing=on" $"background.color=($s.colors.row)"
                "background.corner_radius=8" $"background.height=($s.line_height)"
                "background.padding_left=8" "background.padding_right=8"
                "icon.padding_left=13" "icon.padding_right=10"
                "label.padding_left=0" "label.padding_right=18"
                $"label.color=($s.colors.text)"
                $"label.font=($s.font):Semibold:13.0"
                $"icon=($GLYPHS | get $state)"
                $"icon.color=($hue)"
                $"icon.font=($s.font):Bold:14.0"
                # `entered` only: leaving a row is how you reach the footer it
                # filled, so hiding on `exited` made the text vanish exactly as
                # you went to read it.
                "--subscribe" $n "mouse.entered"
            ]
        }
        for i in 0..<$s.preview_lines {
            let n = pv-name $s $state $i
            # Slot 0 is the WHERE line — which agent this is — so it is styled
            # apart from the message beneath it. A fixed slot can afford that:
            # the styling is set once here and no paint ever touches it.
            let lead = $i == 0
            $args = $args ++ [
                "--add" "item" $n $"popup.($item)"
                "--set" $n "drawing=off"
                $"label.color=(if $lead { (tint $hue '99') } else { $s.colors.dim })"
                $"label.font=($s.font):(if $lead { 'Bold:11.0' } else { 'Italic:12.0' })"
                "label.padding_left=14" "label.padding_right=14"
                # No background at all: the slot is popup.height tall and the
                # row is only text, so a pill here would just box a sentence.
                "icon.drawing=off" "background.drawing=off"
                $"y_offset=(if $lead { 2 } else { 0 })"
            ]
        }
    }
    # Leaving the bar and every popup shuts all three drawers. It lives on an
    # item of its own rather than on a chip because the answer never changes:
    # written once here, never rewritten by a paint.
    let exit = sentinel $s
    $args = $args ++ [
        "--add" "item" $exit $s.position
        "--set" $exit "drawing=off"
        $"script=[ \"$SENDER\" = mouse.exited.global ] || exit 0; exec (close-shell $s)"
        "--subscribe" $exit "mouse.exited.global"
    ]
    let names = $COUNTED | each {|state| chip $s $state }
    $args ++ ["--add" "bracket" (group $s) ...$names
              "--set" (group $s) "background.drawing=on" $"background.color=($s.background)"]
}
