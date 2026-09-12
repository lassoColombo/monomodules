# SketchyBar: three counters, and behind each one a drawer of the agents it
# counts.
#
#      2      3      1
#      └ hover
#        ┌──────────────────────────┐
#        │  2 active                │   head
#        │   nushell-monomodules    │   row 0
#        │   zz-picker-refactor     │   row 1   ← hover this
#        │  home/2 · ~/…/zz         │   pv 0
#        │  All facts verified.     │   pv 1
#        │  Here's the review.      │   pv 2
#        └──────────────────────────┘
#
# HOW THIS DIFFERS FROM v1, and it is most of what is missing. v1 painted like
# this:
#
#   hook → sketchybar --trigger → the daemon wakes → runs render.sh
#        → starts a fresh nu → loads the module → reads the store → --set
#
# A second nu process, ~47ms, and a glue script living in the bar's config. v2
# paints like this:
#
#   hook → --set
#
# ~6.5ms, no event, no daemon round trip, no second process, nothing in
# ~/.config/sketchybar that is ours. It can do that because dispatch already runs
# inside the agent's process with the whole store in hand: there is nobody to ask.
#
# AND v1'S PAINT DIFFER IS GONE. It cached its model on disk so an unchanged bar
# could send nothing, and hand-rolled a per-drawer, per-slot comparison on top of
# that — about sixty lines. Here `project` returns a MAP, one key per slot, and
# `core/dispatch.nu` diffs two of them for every surface there will ever be. A
# row that did not move is not written; a row whose agent is gone arrives in
# `removed` and is switched off. Nothing is cached anywhere.
#
# WHAT THE GATE STILL STOPS, and what it no longer does. `PostToolUse` re-asserts
# `working` many times a turn and projects identically — nothing is sent, which is
# the case that fires constantly. A `Stop` now DOES reach the bar, because the
# message it carries is a row's preview. That is one ~7ms message per turn, and it
# is the price of the preview being right.
#
#   mod.nu    the surface contract — settings, project, apply
#   items.nu  item names, the fixed pool, and the shell a hover runs
#   text.nu   markdown → what a label can show

use ../../core/schema.nu
use items.nu
use text.nu

const SELF = path self

export const INFO = {name: "sketchybar", title: "SketchyBar agent counters"}

# Rosé Pine, to match the rest of the bar. `dim` is the colour a zero wears.
const DEFAULTS = {
    binary: ""              # "" means: find it (see resolve-binary)
    prefix: "an_"
    position: "left"
    font: "MesloLGLDZ Nerd Font"
    background: "0xff26233a"
    rows: 10                # agent rows per drawer; the rest are counted, not drawn
    preview_lines: 12       # preview rows, of which the first is the WHERE line
    preview_width: 110      # characters a preview row may hold; it is NOT wrapped
    row_width: 40           # characters an agent's name may hold
    # `popup.height` is what a drawer actually spaces its rows by, and it
    # DEFAULTS TO THE BAR HEIGHT — 34px, over twice a 12pt line, which is why an
    # untouched drawer is mostly air. The rows' own `background.height` cannot
    # fix it: it sizes the pill, not the slot the pill sits in.
    line_height: 22         # px between popup rows, and the height of a row pill
    colors: {
        working: "0xff9ccfd8"          # foam
        awaiting: "0xfff6c177"         # gold
        needs-attention: "0xffeb6f92"  # love
        dim: "0xff6e6a86"              # muted
        text: "0xffe0def4"             # text
        row: "0xff26233a"              # overlay — a row's own background
        popup: "0xff1f1d2e"            # surface — the drawer behind them
        border: "0xff403d52"           # highlight med
    }
}

const EXTRA_COLORS = ["dim" "text" "row" "popup" "border"]
const NUMBERS = ["rows" "preview_lines" "preview_width" "row_width" "line_height"]

# An ABSOLUTE path to the program, because a hook's PATH is not your shell's PATH
# and a LAUNCHD JOB's is smaller still: the clock runs with /usr/bin:/bin and
# nothing else, so a bare `^sketchybar` silently does nothing there. Resolved once,
# in `settings`, so a missing program is a loud configuration error rather than a
# surface that reports "applied" and paints nothing — which is exactly how this
# was found. It is also baked into every generated script, where PATH is the
# daemon's rather than ours.
# No `-> string` signature: a def annotated that way cannot END in `error make`
# (plan.md §10).
def resolve-binary [given: string] {
    if ($given | is-not-empty) {
        if not ($given | path exists) {
            error make --unspanned {msg: $"sketchybar: no program at '($given)'"}
        }
        return $given
    }
    let found = which "sketchybar" | get -o 0.path | default ""
    if ($found | is-not-empty) { return $found }
    for d in ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin"] {
        let p = $d | path join "sketchybar"
        if ($p | path exists) { return $p }
    }
    error make --unspanned {msg: ("sketchybar: not found. Set `sketchybar.binary: <path>` in the config "
        + "file if it lives somewhere unusual.")}
}

def check-colors [colors: record] {
    if not (($colors | describe) | str starts-with "record") {
        error make --unspanned {msg: $"sketchybar: `colors` must be a map, got ($colors | describe)"}
    }
    let known = $schema.STATES ++ $EXTRA_COLORS
    for k in ($colors | columns) {
        if ($k not-in $known) {
            error make --unspanned {msg: $"sketchybar: '($k)' is not a colour we use \(try: ($known | str join ', ')\)"}
        }
        let v = $colors | get $k
        if (($v | describe) != "string") or (not ($v =~ '^0x[0-9a-fA-F]{8}$')) {
            error make --unspanned {msg: $"sketchybar: the colour for '($k)' must look like 0xAARRGGBB, got ($v | to nuon)"}
        }
    }
}

export def settings [given: record]: nothing -> record {
    for k in ($given | columns | where {|k| $k not-in ($DEFAULTS | columns) }) {
        error make --unspanned {msg: $"sketchybar: '($k)' is not a setting \(try: ($DEFAULTS | columns | str join ', ')\)"}
    }
    check-colors ($given.colors? | default {})
    # A pool is built from these, so a zero or a string here would produce a
    # drawer with no slots in it and no hint as to why.
    for k in ($NUMBERS | where {|k| $k in ($given | columns) }) {
        let v = $given | get $k
        if (($v | describe) != "int") or ($v < 1) {
            error make --unspanned {msg: $"sketchybar: `($k)` must be a positive number, got ($v | to nuon)"}
        }
    }
    $DEFAULTS
    | merge ($given | reject --optional colors)
    | upsert colors ($DEFAULTS.colors | merge ($given.colors? | default {}))
    | upsert binary (resolve-binary ($given.binary? | default ""))
}

# ── describing ───────────────────────────────────────────────────────────────

# Elide from the LEFT. A path's tail is the part that identifies it, so a
# directory too long for a preview row keeps its end, not its beginning — and
# the cut snaps forward to the next separator when one is close, because
# "…ojects/personal" reads worse than "…/personal" and is no more informative.
def tail-to [s: string, n: int]: nothing -> string {
    let cs = $s | split chars
    if ($cs | length) <= $n { return $s }
    let kept = $cs | last ([0 ($n - 1)] | math max)
    let at = $kept | enumerate | where {|e| $e.item == "/" } | get -o 0.index
    let snapped = if ($at != null) and ($at <= 12) { $kept | skip $at } else { $kept }
    "…" + ($snapped | str join)
}

# Which agent this is, in one line: where it lives, and what it is working on.
# The row above only has room for a name, and two agents may well share one.
def where-of [r: record, s: record]: nothing -> string {
    let z = $r.zellij? | default {}
    let sess = $z.session? | default ""
    let place = if ($sess | is-not-empty) {
        $"($sess)/($z.tab_base? | default ($z.tab_id? | default '?'))"
    } else {
        $r.client? | default "agent"
    }
    let dir = $r.cwd? | default "" | str replace $nu.home-dir "~"
    if ($dir | is-empty) { return (text cut-to $place $s.preview_width) }
    let room = $s.preview_width - (($place | split chars | length) + 3)
    $"($place) · (tail-to $dir $room)"
}

# The agent's own name when it has one — the naming convention is what makes a
# session recognisable — and the directory it is working in when it does not.
def label-of [r: record, s: record]: nothing -> string {
    let name = $r.name? | default ""
    let raw = if ($name | is-not-empty) {
        $name
    } else {
        let dir = $r.cwd? | default "" | path basename
        if ($dir | is-not-empty) { $dir } else { $r.id? | default "agent" | str substring 0..7 }
    }
    text quotable (text cut-to $raw $s.row_width)
}

# The preview, ready to be baked into a shell command: the WHERE line, then the
# message with its markdown taken off, one source line per row and NOTHING
# WRAPPED — a drawer is wide, and a sentence spilling onto a second row costs a
# slot and reads as two thoughts. What does not fit is cut with an ellipsis.
def lines-of [r: record, s: record]: nothing -> list<string> {
    let source = text plain ($r.message? | default "")
    let body = text lay-out $source $s.preview_width ($s.preview_lines - 1)
    let shown = if ($body | is-empty) { ["—"] } else { $body }
    ([(where-of $r $s)] ++ $shown) | each {|l| text quotable $l }
}

# One key per SLOT on the bar, which is what lets `core/dispatch.nu` do the whole
# of the diffing: a row that did not move is not in `changed`, and a row whose
# agent has gone arrives in `removed` with its old value.
#
#   count|working     2
#   row|working|0     {label: "zz-picker-refactor", lines: [...]}
#
# Idle agents appear nowhere: an agent with nothing to say does not deserve a
# number. Within a drawer the oldest is first — every row shares a state, so
# "who has been waiting longest" is the only ordering that says anything.
export def project [records: list<record>, s: record]: nothing -> record {
    mut out = {}
    for state in $items.COUNTED {
        let here = $records
            | where {|r| ($r.state? | default "idle") == $state }
            | sort-by {|r| $r.state_since? | default "" } {|r| $r.id? | default "" }
        $out = ($out | upsert $"count|($state)" ($here | length))
        for e in ($here | first $s.rows | enumerate) {
            $out = ($out | upsert $"row|($state)|($e.index)" {
                label: (label-of $e.item $s)
                lines: (lines-of $e.item $s)
            })
        }
    }
    $out
}

# ── writing ──────────────────────────────────────────────────────────────────

def write-args [key: string, v: any, s: record]: nothing -> list<string> {
    let p = $key | split row "|"
    match ($p | get 0) {
        "count" => (items counter-args $s ($p | get 1) $v)
        "row" => (items row-args $s ($p | get 1) ($p | get 2 | into int) $v)
        _ => []
    }
}

def erase-args [key: string, s: record]: nothing -> list<string> {
    let p = $key | split row "|"
    # Only rows are ever removed. The three counts are fixed keys, so an emptied
    # drawer goes to zero rather than disappearing.
    if ($p | get 0) == "row" {
        items row-off-args $s ($p | get 1) ($p | get 2 | into int)
    } else { [] }
}

# The repaint, as DATA. Separated from `apply` so the tests can read exactly what
# would be sent without a bar being installed — the same trick `project` plays for
# the thinking.
export def message [changed: record, removed: record, s: record]: nothing -> list<string> {
    let on = $changed | columns | each {|k| write-args $k ($changed | get $k) $s } | flatten
    let off = $removed | columns | each {|k| erase-args $k $s } | flatten
    $on ++ $off
}

export def apply [changed: record, removed: record, s: record]: nothing -> nothing {
    let m = message $changed $removed $s
    if ($m | is-not-empty) { ^$s.binary ...$m | complete | ignore }
}

# ── installation ─────────────────────────────────────────────────────────────

export def install-message [s: record]: nothing -> list<string> { items pool-args $s }

export def install [s: record]: nothing -> nothing {
    ^$s.binary ...(install-message $s) | complete | ignore
}

export def wiring []: nothing -> string {
    let root = $SELF | path dirname | path dirname | path dirname
    ([ "Add one line to ~/.config/sketchybar/sketchybarrc, where you want the"
       "counters to sit among your other items:"
       ""
       $"  ($nu.current-exe) -n --no-std-lib -c 'use ($root); agent-notify2 surfaces install sketchybar'"
       ""
       "That creates the three counters, their drawers and their preview rows,"
       "then paints them from the store. No plugin script, no glyphs, no colours"
       "— they are all in agent-notify's own config file. Hovering a counter"
       "opens its drawer; hovering a row shows that agent's last message."
       ""
       "The periodic check that removes dead agents is NOT here: it is its own"
       "thing, so that turning the bar off cannot turn it off too."
       ""
       "  agent-notify2 clock install" ] | str join "\n")
}
