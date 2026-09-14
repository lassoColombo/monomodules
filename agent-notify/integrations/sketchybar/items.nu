# Item names, the fixed pool, and the shell the bar runs on its own.
#
# Everything here is PURE: functions that return argument lists, never a
# subprocess. `mod.nu` sends what they build, and the test suite reads it with
# no bar installed at all.
#
# THE GENERATED SHELL is the part worth understanding. A drawer opens on hover
# and a row's preview fills on hover, and SketchyBar has only one way to react
# to a mouse: run an item's `script`. v1 pointed those scripts at files in
# ~/.config/sketchybar/plugins, and the row's one started a whole nushell — read
# the session-store, wrap the text, send it — about 47ms for every row the
# pointer brushed past.
#
# Here the script IS the answer. A `script` is handed to a shell (probed: the
# daemon expands $SENDER and honours quoting), so we write the sketchybar
# command that the hover should run and session-store it on the item. Two
# consequences:
#
#   nothing of ours lives in the bar's config directory — still true, which is
#   the whole v2 bargain; and
#
#   a hover costs one `sh` plus one client, ~7ms, with no store read and
#   nothing that can go stale, because the text was written by the same paint
#   that wrote the row.
#
# The price is that a preview's text is baked into a shell command, so it must
# be safe to single-quote. `quotable`, below, is the whole of that: a literal
# `'` becomes `’` and control characters become spaces. Probed on the real
# daemon — inside single quotes `$HOME` and backticks stay literal.
#
# IT IS APPLIED WHERE THE QUOTE IS WRITTEN, in `hover-shell`, and nowhere else.
# It used to be applied in `project`, which put a transport quirk of one display
# into the map dispatch diffs — so the projection said the agent had written
# `it’s` when it had written `it's` — and escaped a row's LABEL, which is argv
# and never sees a shell at all. Escaping is what `apply` does to text on its
# way out; it is not part of what should be shown.
#
# EVERY SCRIPT GUARDS ON $SENDER. An item's script also runs on a forced
# `--update`, which SketchyBar sends at bar load; without the guard the bar
# would open a drawer nobody hovered.

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

# ── names ─────────────────────────────────────────────────────────────────────
# "needs-attention" is not a legal item name, and a name is the only handle the
# bar gives us, so the suffix is fixed here and nowhere else.

def suffix [state: string]: nothing -> string {
    if $state == "needs-attention" { "attention" } else { $state }
}

export def item-name [settings: record, state: string]: nothing -> string { $"($settings.prefix)(suffix $state)" }
export def head [settings: record, state: string]: nothing -> string { $"(item-name $settings $state).head" }
export def row-name [settings: record, state: string, index: int]: nothing -> string { $"(item-name $settings $state).row.($index)" }
export def pv-name [settings: record, state: string, index: int]: nothing -> string { $"(item-name $settings $state).pv.($index)" }
export def group [settings: record]: nothing -> string { $"($settings.prefix)group" }
export def exit-item [settings: record]: nothing -> string { $"($settings.prefix)exit" }

# Same hue, less alpha: a counter at zero stays recognisable by colour instead
# of going grey, so the three icons read at a glance the way the wifi and
# battery widgets do.
export def tint [color: string, alpha: string]: nothing -> string {
    $"0x($alpha)($color | str substring 4..)"
}

# ── the shell a hover runs ────────────────────────────────────────────────────

const GUARD = "[ \"$SENDER\" = mouse.entered ] || exit 0; exec "

# Safe to wrap in SINGLE QUOTES, which is how a preview line reaches the bar. On
# the real daemon `$HOME` and backticks are already literal inside single
# quotes, so a lone `'` is the whole of the danger and one substitution is the
# whole of the escaping — and a typographic apostrophe is what the text wanted
# anyway. Control characters go too: a stray \r would end the command line
# early.
#
# CHARACTER FOR CHARACTER, which is what lets it run last. A line has already
# been cut to `preview_width` by then, and an escape that changed the length
# would push it back over.
def quotable [text: string]: nothing -> string {
    $text | str replace --all "'" "’" | str replace --all --regex '[\x00-\x1f]' " "
}

# Shut every drawer. Static — it depends on nothing that a paint can change —
# so it is written once, at install, and never rewritten.
export def close-args [settings: record]: nothing -> list<string> {
    $COUNTED | each {|st| ["--set" (item-name $settings $st) "popup.drawing=off"] } | flatten
}

def close-shell [settings: record]: nothing -> string {
    $"($settings.binary) (close-args $settings | str join ' ')"
}

# Hovering a item-name opens ITS drawer and shuts the other two, because sliding
# along the bar must not leave a trail of open popups behind. It also blanks its
# own preview footer, so a drawer never reappears showing the last row you read.
#
# An EMPTY drawer opens NOTHING — popping "All clear" at a pointer merely
# crossing the bar is noise — but it still CLOSES the others: moving sideways
# off a counter means you are done with the one you left. v1 needed a flag file
# on disk to know which counters were empty; here the count is already in hand,
# and the script is rewritten only when it crosses zero.
export def open-shell [settings: record, state: string, count: int]: nothing -> string {
    if $count == 0 { return ($GUARD + (close-shell $settings)) }
    let others = $COUNTED | where {|st| $st != $state }
        | each {|st| ["--set" (item-name $settings $st) "popup.drawing=off"] } | flatten
    let blank = 0..<$settings.preview_lines | each {|index| ["--set" (pv-name $settings $state $index) "drawing=off"] } | flatten
    let args = ["--set" (item-name $settings $state) "popup.drawing=on"] ++ $others ++ $blank
    $GUARD + $"($settings.binary) ($args | str join ' ')"
}

# WHAT A ROW IS, IN THE ONE THING A LABEL CAN SAY IT WITH (D62). A SketchyBar
# item has no ANSI and no runs: it has ONE `label.color`, so a row gets one
# colour and its kind picks which. `core/markdown.nu` says what each row is and
# stops there — the same split as everywhere else here, and the reason the
# picker can paint the same two meanings in ANSI without sharing a line of this.
#
# WHICH MEANS THE COLOUR IS DECIDED PER PAINT, not once at install. The pool
# cannot hold it: whether row 4 is a heading depends on what the agent wrote.
def ink [settings: record, hue: string, kind: string]: nothing -> string {
    match $kind {
        "where" => (tint $hue "99")
        "head" => $settings.colors.head
        "code" => $settings.colors.code
        _ => $settings.colors.dim
    }
}

# One row's preview, as the command that will show it. Called at PAINT time with
# the rows already wrapped and kinded, so the hover itself does no thinking.
export def hover-shell [settings: record, state: string, rows: list<record>]: nothing -> string {
    let hue = $settings.colors | get $state
    let args = 0..<$settings.preview_lines | each {|index|
        let r = $rows | get -o $index
        if $r == null {
            ["--set" (pv-name $settings $state $index) "drawing=off"]
        } else {
            ["--set" (pv-name $settings $state $index)
             $"'label=(quotable $r.t)'"
             $"label.color=(ink $settings $hue $r.k)"
             "drawing=on"]
        }
    } | flatten
    $GUARD + $"($settings.binary) ($args | str join ' ')"
}

# ── the shell a CLICK runs ────────────────────────────────────────────────────
#
# Where `cli/jump.nu` is, worked out from where this file is. Baked as an
# ABSOLUTE path into every click script, because the bar daemon's working
# directory is not ours and its PATH is launchd's.
const JUMP_MODULE = (path self | path dirname | path dirname | path dirname | path join "cli" "jump.nu")

# A CLICK RUNS THE MODULE; IT DOES NOT GET A BAKED ARGV (plan.md D75). That is
# the one place D44 does not reach, and the reason is not the process — it is
# WHEN THE DECISION IS MADE. A hover shows text the same paint wrote, so baking
# it cannot be stale. A jump is a decision about where an agent is NOW, and a
# pane can move with no state change at all, so a paint-time argv can send you
# somewhere nobody is.
#
# The cost of deciding at click time is one nushell, and what that costs depends
# entirely on what it is pointed at. Measured, median of 15:
#
#   nu -n --no-std-lib -c ''                   16.5ms   the floor
#   … -c 'use cli/jump.nu; jump <id>'          22.6ms   what this runs
#   … -c 'use agent-notify; …'                 97.3ms   through the facade
#
# So it points at `cli/jump.nu` and not at the module. 22.6ms after a deliberate
# click is invisible — it is less than half what ONE of v1's hovers cost, and a
# hover fires at pointer frequency where a click fires once.
#
# The drawers shut first, because you are about to be looking at something else
# and a popup left open over another application is litter.
#
# QUOTING: the nushell payload is wrapped in SINGLE QUOTES for the shell, so
# `$HOME` and backticks inside it stay literal (probed on the real daemon —
# see `quotable`). An id is a uuid and cannot carry a quote; the module path
# could in principle, and a path containing `'` is the one case this cannot
# express. It is not defended against, because defending would mean mangling a
# path we need to be exact.
export def click-shell [settings: record, id: string]: nothing -> string {
    let shut = $"($settings.binary) (close-args $settings | str join ' ')"
    let jump = $"($nu.current-exe) -n --no-std-lib -c 'use \"($JUMP_MODULE)\"; jump ($id)'"
    $"($shut); exec ($jump)"
}

# ── what a paint writes ───────────────────────────────────────────────────────

# A drawer's size changed: the item-name's number, its header, and — since an
# empty drawer opens nothing — the script behind it.
export def counter-args [settings: record, state: string, count: int]: nothing -> list<string> {
    let item = item-name $settings $state
    let hue = $settings.colors | get $state
    let label = if $count == 0 { "  All clear"
        } else if $count > $settings.rows { $"  ($count) active · ($settings.rows) shown"
        } else { $"  ($count) active" }
    [ "--set" $item
      $"icon.color=(if $count > 0 { $hue } else { (tint $hue '66') })"
      $"label=($count)"
      $"label.color=(if $count > 0 { $hue } else { $settings.colors.dim })"
      $"script=(open-shell $settings $state $count)"
      "--set" (head $settings $state)
      $"icon=(if $count == 0 { '✓' } else { '' })"
      $"icon.color=(if $count == 0 { $settings.colors.working } else { $settings.colors.dim })"
      $"label=($label)" ]
}

# One agent's row: what it says, what hovering it shows, and where clicking it
# takes you.
export def row-args [settings: record, state: string, index: int, value: record]: nothing -> list<string> {
    [ "--set" (row-name $settings $state $index)
      $"label=($value.label)"
      "drawing=on"
      $"script=(hover-shell $settings $state $value.lines)"
      # A row with no id behind it gets NO click rather than a click that goes
      # nowhere. It cannot happen from a live paint — `render-items` always has
      # the record — but a value written by an older paint and diffed against by
      # this one can, and an empty setting is how SketchyBar is told to forget.
      $"click_script=(if (($value.id? | default '') | is-empty) { '' } else { (click-shell $settings $value.id) })" ]
}

# A row with no agent behind it any more. BOTH scripts go: a 1KB preview of an
# agent that is gone must not be left sitting on the item, and neither must a
# click that would take you to a pane it no longer has.
export def row-off-args [settings: record, state: string, index: int]: nothing -> list<string> {
    ["--set" (row-name $settings $state $index) "drawing=off" "script=" "click_script="]
}

# ── the pool, created once ────────────────────────────────────────────────────
# WHAT THIS COSTS, measured on the real bar, because the numbers chose the shape:
#
#   --add 70 items in ONE message    40.8ms   ← once, at bar load
#   --set 70 labels in ONE message   18.6ms   ← a paint touches one or two
#
# So the pool is built in a single message at install and never added to or
# removed from again. v1 learned the other way, rebuilding ~43 items per paint
# and pinning the daemon near 40% CPU — which is what used to make bar clicks
# lag.
#
# NO TIMER HERE. An earlier version hung a hidden `update_freq=30` item off this
# pool to prune dead agents and repaint. It worked, and it was still wrong: it
# made a core guarantee depend on one optional display being installed. The
# prune-daemon is its own thing now (core/prune-daemon/), and this file is
# only a display again.
export def preallocate-args [settings: record]: nothing -> list<string> {
    mut args = []
    for state in $COUNTED {
        let item = item-name $settings $state
        let hue = $settings.colors | get $state
        # Idempotent: a re-run wipes this drawer's children first, so changing
        # `rows` in the config cannot leave orphans behind. The regex needs the
        # dot, so the item-name itself survives and keeps its place on the bar.
        $args = $args ++ ["--remove" $"/($item)\\..*/"]
        $args = $args ++ [
            "--add" "item" $item $settings.position
            "--set" $item
            $"icon=($GLYPHS | get $state)"
            $"icon.font=($settings.font):Bold:15.0"
            $"icon.color=(tint $hue '66')"
            "label=0"
            $"label.font=($settings.font):Semibold:13.0"
            $"label.color=($settings.colors.dim)"
            # popup.align=left so a drawer opens rightward; align=right ran it
            # off the screen edge.
            #
            # popup.height is THE VERTICAL SPACING BETWEEN ROWS, and left alone
            # it is the BAR's height — 34px around a 12pt line, which is why an
            # untouched drawer is nine tenths air. A row's own background.height
            # cannot correct it: that sizes the pill, not the slot.
            $"popup.height=($settings.line_height)"
            "popup.align=left" "popup.background.drawing=on"
            $"popup.background.color=($settings.colors.popup)"
            "popup.background.corner_radius=10" "popup.background.border_width=1"
            $"popup.background.border_color=($settings.colors.border)"
            $"script=(open-shell $settings $state 0)"
            $"click_script=(close-shell $settings)"
            "--subscribe" $item "mouse.entered"
        ]
        $args = $args ++ [
            "--add" "item" (head $settings $state) $"popup.($item)"
            "--set" (head $settings $state)
            $"icon.font=($settings.font):Bold:11.0"
            $"label.font=($settings.font):Bold:11.0"
            $"label.color=($settings.colors.dim)"
            $"icon.color=($settings.colors.dim)"
            "label=  All clear" "icon=✓"
            "icon.padding_left=14" "label.padding_right=14"
            "background.drawing=off" "y_offset=1"
        ]
        # A row's `click_script` is written per PAINT, not here, because it
        # carries that row's agent id — see `click-shell`. The pool only has to
        # subscribe to the hover; a click needs no subscription.
        for index in 0..<$settings.rows {
            let slot = row-name $settings $state $index
            $args = $args ++ [
                "--add" "item" $slot $"popup.($item)"
                "--set" $slot "drawing=off"
                "background.drawing=on" $"background.color=($settings.colors.row)"
                "background.corner_radius=8" $"background.height=($settings.line_height)"
                "background.padding_left=8" "background.padding_right=8"
                "icon.padding_left=13" "icon.padding_right=10"
                "label.padding_left=0" "label.padding_right=18"
                $"label.color=($settings.colors.text)"
                $"label.font=($settings.font):Semibold:13.0"
                $"icon=($GLYPHS | get $state)"
                $"icon.color=($hue)"
                $"icon.font=($settings.font):Bold:14.0"
                # `entered` only: leaving a row is how you reach the footer it
                # filled, so hiding on `exited` made the text vanish exactly as
                # you went to read it.
                "--subscribe" $slot "mouse.entered"
            ]
        }
        for index in 0..<$settings.preview_lines {
            let slot = pv-name $settings $state $index
            # Slot 0 is the WHERE line — which agent this is — so it is styled
            # apart from the message beneath it. The FONT is set once here and
            # no paint touches it; the COLOUR written here is only the pool's
            # resting state, because `hover-shell` decides it per row from what
            # the agent actually wrote.
            let lead = $index == 0
            $args = $args ++ [
                "--add" "item" $slot $"popup.($item)"
                "--set" $slot "drawing=off"
                $"label.color=(if $lead { (tint $hue '99') } else { $settings.colors.dim })"
                $"label.font=($settings.font):(if $lead { 'Bold:11.0' } else { 'Italic:12.0' })"
                "label.padding_left=14" "label.padding_right=14"
                # No background at all: the slot is popup.height tall and the
                # row is only text, so a pill here would just box a sentence.
                "icon.drawing=off" "background.drawing=off"
                $"y_offset=(if $lead { 2 } else { 0 })"
            ]
        }
    }
    # Leaving the bar and every popup shuts all three drawers. It lives on an
    # item of its own rather than on a item-name because the answer never
    # changes: written once here, never rewritten by a paint.
    let exit = exit-item $settings
    $args = $args ++ [
        "--add" "item" $exit $settings.position
        "--set" $exit "drawing=off"
        $"script=[ \"$SENDER\" = mouse.exited.global ] || exit 0; exec (close-shell $settings)"
        "--subscribe" $exit "mouse.exited.global"
    ]
    let names = $COUNTED | each {|state| item-name $settings $state }
    $args ++ ["--add" "bracket" (group $settings) ...$names
              "--set" (group $settings) "background.drawing=on" $"background.color=($settings.background)"]
}
