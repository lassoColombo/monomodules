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
#        → starts a fresh nu → loads the module → reads the session-store → --set
#
# A second nu process, ~47ms, and a glue script living in the bar's config. v2
# paints like this:
#
#   hook → --set
#
# ~6.5ms, no event, no daemon round trip, no second process, nothing in
# ~/.config/sketchybar that is ours. It can do that because dispatch already
# runs inside the agent's process with the whole session-store in hand: there is
# nobody to ask.
#
# AND v1'S PAINT DIFFER IS GONE. It cached its model on disk so an unchanged bar
# could send nothing, and hand-rolled a per-drawer, per-slot comparison on top
# of that — about sixty lines. Here `project` returns a MAP, one key per slot,
# and `core/dispatch.nu` diffs two of them for every display there will ever be.
# A row that did not move is not written; a row whose agent is gone arrives in
# `removed` and is switched off. Nothing is cached anywhere.
#
# WHAT THE GATE STILL STOPS, and what it no longer does. `PostToolUse`
# re-asserts `working` many times a turn and projects identically — nothing is
# sent, which is the case that fires constantly. A `Stop` now DOES reach the
# bar, because the message it carries is a row's preview. That is one ~7ms
# message per turn, and it is the price of the preview being right.
#
# AND SINCE STEP 13 A DRAWER CAN OPEN ITSELF. A counter going from 2 to 3 looks
# the same whether it happened now or twenty minutes ago, so an agent that
# reports anything other than "still going" lights its chip, opens its drawer on
# its own words with its row lit inside, and a few seconds later takes all of
# that back. It needed no new state anywhere: `state_since` already says when a
# state changed, so `render-items` derives it and `flash` is one more key in the
# map — raised when it appears, undone when it goes, by the same diff as every
# row. The taking-away is the interesting half and it lives in `items.nu`.
#
# AND THE FOOTER SCROLLS. It holds `preview_depth` rows and shows a window over
# them, so the wheel turns slots on and off over words a paint already wrote —
# no text moves, which keeps the one hazard this display has (agent prose going
# through a shell) off the scroll path entirely.
#
#   mod.nu    the display contract — settings, project, apply
#   items.nu  item names, the fixed pool, the shell a hover runs, the one the
#             flash's timer runs and the one a wheel runs — which is also where
#             those shells' escaping lives, at the point of quoting
#
# The markdown a message is written in is flattened by `core/markdown.nu`, which
# lived here until the picker's preview became its second reader.

use ../../core/session-schema.nu STATES
use ../../core/markdown.nu
use items.nu

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
    preview_lines: 12       # preview rows SHOWN, of which the first is the WHERE line
    # …and how many the footer HOLDS, which is how far a scroll can go. The rows
    # past the first screenful are written to the bar by the same paint and left
    # switched off, so scrolling is `drawing=on` and nothing else — see
    # `items.nu`. A message longer than this is still cut with an ellipsis.
    preview_depth: 40
    preview_width: 110      # characters a preview row may hold; prose is wrapped to it
    row_width: 40           # characters an agent's name may hold
    # `popup.height` is what a drawer actually spaces its rows by, and it
    # DEFAULTS TO THE BAR HEIGHT — 34px, over twice a 12pt line, which is why an
    # untouched drawer is mostly air. The rows' own `background.height` cannot
    # fix it: it sizes the pill, not the slot the pill sits in.
    line_height: 22         # px between popup rows, and the height of a row pill
    # THE FLASH — how long an arrival stays lit, and whether its drawer opens
    # itself with it. Seconds rather than a switch, because the only question
    # anyone actually has about a notification is how long it sits there; 0 is
    # how you say never. See `items.nu`, where the whole of it lives.
    flash_seconds: 6
    flash_drawer: true
    colors: {
        working: "0xff9ccfd8"          # foam
        awaiting: "0xfff6c177"         # gold
        needs-attention: "0xffeb6f92"  # love
        dim: "0xff6e6a86"              # muted — the message body
        text: "0xffe0def4"             # text
        row: "0xff26233a"              # overlay — a row's own background
        popup: "0xff1f1d2e"            # display — the drawer behind them
        border: "0xff403d52"           # highlight med
        # The preview's two kinds (D62). A drawer's body sits at `dim` on
        # purpose — it is the second thing you read — so both of these are a
        # step up from it rather than a different loudness of the same hue.
        head: "0xffebbcba"             # rose — a heading, the palette's pop
        code: "0xffc4a7e7"             # iris — the hue that carries code
    }
}

const EXTRA_COLORS = ["dim" "text" "row" "popup" "border" "head" "code"]
# Sizes a POOL is built from: a zero here is a drawer with no slots in it.
const NUMBERS = ["rows" "preview_lines" "preview_depth" "preview_width" "row_width" "line_height"]
# A span of time, where zero is a legal answer and means "do not".
const SPANS = ["flash_seconds"]
const FLAGS = ["flash_drawer"]

# An ABSOLUTE path to the program, because a hook's PATH is not your shell's
# PATH and a LAUNCHD JOB's is smaller still: the prune-daemon runs with
# /usr/bin:/bin and nothing else, so a bare `^sketchybar` silently does nothing
# there. Resolved once, in `settings`, so a missing program is a loud
# configuration error rather than a display that reports "applied" and paints
# nothing — which is exactly how this was found. It is also baked into every
# generated script, where PATH is the daemon's rather than ours. No `-> string`
# signature: a def annotated that way cannot END in `error make` (plan.md §10).
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
    let known_keys = $STATES ++ $EXTRA_COLORS
    for k in ($colors | columns) {
        if ($k not-in $known_keys) {
            error make --unspanned {msg: $"sketchybar: '($k)' is not a colour we use \(try: ($known_keys | str join ', ')\)"}
        }
        let value = $colors | get $k
        if (($value | describe) != "string") or (not ($value =~ '^0x[0-9a-fA-F]{8}$')) {
            error make --unspanned {msg: $"sketchybar: the colour for '($k)' must look like 0xAARRGGBB, got ($value | to nuon)"}
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
        let value = $given | get $k
        if (($value | describe) != "int") or ($value < 1) {
            error make --unspanned {msg: $"sketchybar: `($k)` must be a positive number, got ($value | to nuon)"}
        }
    }
    for k in ($SPANS | where {|k| $k in ($given | columns) }) {
        let value = $given | get $k
        if (($value | describe) != "int") or ($value < 0) {
            error make --unspanned {msg: $"sketchybar: `($k)` must be a number of seconds, 0 for never, got ($value | to nuon)"}
        }
    }
    for k in ($FLAGS | where {|k| $k in ($given | columns) }) {
        let value = $given | get $k
        if ($value | describe) != "bool" {
            error make --unspanned {msg: $"sketchybar: `($k)` must be true or false, got ($value | to nuon)"}
        }
    }
    let merged = $DEFAULTS
        | merge ($given | reject --optional colors)
        | upsert colors ($DEFAULTS.colors | merge ($given.colors? | default {}))
        | upsert binary (resolve-binary ($given.binary? | default ""))
    # The one check that needs two settings at once: the footer cannot hold less
    # than it shows, and a pool built that way would have a window hanging off
    # the end of it.
    if $merged.preview_depth < ($merged.preview_lines - 1) {
        error make --unspanned {msg: ("sketchybar: `preview_depth` is how many preview rows the drawer HOLDS "
            + $"and cannot be less than the ($merged.preview_lines - 1) it shows \(`preview_lines` - 1\)")}
    }
    $merged
}

# ── describing ────────────────────────────────────────────────────────────────

# Elide from the LEFT. A path's tail is the part that identifies it, so a
# directory too long for a preview row keeps its end, not its beginning — and
# the cut snaps forward to the next separator when one is close, because
# "…ojects/personal" reads worse than "…/personal" and is no more informative.
def tail-to [text: string, width: int]: nothing -> string {
    let cs = $text | split chars
    if ($cs | length) <= $width { return $text }
    let kept = $cs | last ([0 ($width - 1)] | math max)
    let at = $kept | enumerate | where {|e| $e.item == "/" } | get -o 0.index
    let snapped = if ($at != null) and ($at <= 12) { $kept | skip $at } else { $kept }
    "…" + ($snapped | str join)
}

# Which agent this is, in one line: where it lives, and what it is working on.
# The row above only has room for a name, and two agents may well share one.
def where-of [record: record, settings: record]: nothing -> string {
    let z = $record.zellij? | default {}
    let sess = $z.session? | default ""
    let location_label = if ($sess | is-not-empty) {
        $"($sess)/($z.tab_base? | default ($z.tab_id? | default '?'))"
    } else {
        $record.agent? | default "agent"
    }
    let dir = $record.cwd? | default "" | str replace $nu.home-dir "~"
    if ($dir | is-empty) { return (markdown cut-to $location_label $settings.preview_width) }
    let room = $settings.preview_width - (($location_label | split chars | length) + 3)
    $"($location_label) · (tail-to $dir $room)"
}

# The agent's own name when it has one — the naming convention is what makes a
# session recognisable — and the directory it is working in when it does not.
def label-of [record: record, settings: record]: nothing -> string {
    let name = $record.name? | default ""
    let raw = if ($name | is-not-empty) {
        $name
    } else {
        let dir = $record.cwd? | default "" | path basename
        if ($dir | is-not-empty) { $dir } else { $record.id? | default "agent" | str substring 0..7 }
    }
    markdown cut-to $raw $settings.row_width
}

# The preview, as the agent's own words: the WHERE line, then the message with
# its markdown taken off, one source line per row and NOTHING WRAPPED — a drawer
# is wide, and a sentence spilling onto a second row costs a slot and reads as
# two thoughts. What does not fit is cut with an ellipsis.
#
# NOT ESCAPED HERE. `items.nu` makes it safe to single-quote at the moment it
# writes the quote; a projection says what should be SHOWN, and how one display
# gets it onto a wire is not part of that.
def lines-of [record: record, settings: record]: nothing -> list<record> {
    # As deep as the footer HOLDS, not as deep as it shows — the rest is written
    # to the bar switched off, and a scroll is what turns it on.
    let rows = $settings.preview_depth
    let source = markdown plain-md ($record.message? | default "") $settings.preview_width ($rows + 1)
    let body = markdown lay-out $source $settings.preview_width $rows
    let shown = if ($body | is-empty) { [{k: "text", t: "—"}] } else { $body }
    # `where` is this display's own kind — the markdown never produces one — and
    # it is what keeps slot 0 in the state's hue while the message beneath it
    # takes its colours from what the agent wrote.
    [{k: "where", t: (where-of $record $settings)}] ++ $shown
}

# WHICH AGENT IS NEWS, and the reason the flash needs no memory anywhere.
# `state_since` is already the moment the state changed, so *has this just
# happened?* is a question the record answers about itself: nothing is stored,
# nothing is compared against a previous paint, and an agent that has been
# waiting all morning is not news however many times it is re-rendered.
#
# THE MOST RECENT ONE WINS, because a newer announcement supersedes an older
# one — which is what a notification does everywhere else. And the deadline it
# carries is `state_since` plus the window rather than `now` plus the window, so
# an unrelated paint that re-sends the same flash cannot push its end away.
#
# This is the ONE thing in the whole display that is not a pure function of the
# records. It has to be: "recently" is a question about the clock. Both halves
# of a diff are rendered in the same breath, so it never makes the two disagree.
def announcement [records: list<record>, settings: record]: nothing -> record {
    if $settings.flash_seconds < 1 { return {} }
    let now = date now
    let window = $settings.flash_seconds * 1sec
    $records
    | where {|record| ($record.state? | default "idle") in $items.ANNOUNCED }
    | each {|record|
        let at = try { $record.state_since | into datetime } catch { null }
        if ($at == null) or (($now - $at) >= $window) { null } else {
            {id: ($record.id? | default ""), at: $at, until: (($at + $window) | format date "%s" | into int)}
        } }
    | compact
    | sort-by at
    | last 1
    | get -o 0
    | default {}
}

def is-lit [id: string, lit: string]: nothing -> bool { ($lit | is-not-empty) and ($id == $lit) }

# One key per SLOT on the bar, which is what lets `core/dispatch.nu` do the
# whole of the diffing: a row that did not move is not in `changed`, and a row
# whose agent has gone arrives in `removed` with its old value.
#
#   count|working     {n: 2, only: ""}
#   row|working|0     {id: "6923c0bc-…", label: "zz-picker-refactor", lines: [...],
#                      flash: false}
#   flash             {state: "awaiting", index: 1, until: 1789386573, lines: [...]}
#
# A COUNTER CARRIES WHO IT COUNTS, not only how many, because a counter is a
# thing you click. `only` is the agent's id when the counter stands for exactly
# ONE — the only time there is a correct session to go to — and "" for none or
# many, where the drawer is the answer instead.
#
# Idle agents appear nowhere: an agent with nothing to say does not deserve a
# number. Within a drawer the oldest is first — every row shares a state, so
# "who has been waiting longest" is the only ordering that says anything.
#
# `flash` is there only while something is announcing itself, so it arrives in
# `changed` when a flash is raised and in `removed` when the agent leaves the
# state before the window is out — and the one display key that means "undo
# this" gets its undo from the same machinery as every other.
export def render-items [records: list<record>, settings: record]: nothing -> record {
    let news = announcement $records $settings
    let lit = $news.id? | default ""
    let until = $news.until? | default 0
    mut out = {}
    mut flash = {}
    for state in $items.COUNTED {
        let here = $records
            | where {|record| ($record.state? | default "idle") == $state }
            | sort-by {|record| $record.state_since? | default "" } {|record| $record.id? | default "" }
        $out = ($out | upsert $"count|($state)" {
            n: ($here | length)
            only: (if ($here | length) == 1 { $here | first | get -o id | default "" } else { "" })
        })
        # The chip lights even when the agent it announces is past the cap and
        # has no row to light — the number moving is itself the news.
        if ($here | any {|record| is-lit ($record.id? | default "") $lit }) {
            $flash = {state: $state, index: null, until: $until, lines: []}
        }
        for e in ($here | first $settings.rows | enumerate) {
            let id = $e.item.id? | default ""
            let lines = lines-of $e.item $settings
            $out = ($out | upsert $"row|($state)|($e.index)" {
                # The id is here so a click can be baked without a lookup, and
                # so a row whose OCCUPANT changed repaints even when the two
                # agents happen to look identical.
                id: $id
                label: (label-of $e.item $settings)
                lines: $lines
                flash: (is-lit $id $lit)
            })
            if (is-lit $id $lit) { $flash = ($flash | merge {index: $e.index, lines: $lines}) }
        }
    }
    if ($flash | is-empty) { $out } else { $out | upsert flash $flash }
}

# ── writing ───────────────────────────────────────────────────────────────────

def write-args [key: string, value: any, settings: record]: nothing -> list<string> {
    let p = $key | split row "|"
    match ($p | get 0) {
        "count" => (items counter-args $settings ($p | get 1) $value)
        "row" => (items row-args $settings ($p | get 1) ($p | get 2 | into int) $value)
        _ => []
    }
}

def erase-args [key: string, settings: record]: nothing -> list<string> {
    let p = $key | split row "|"
    # Only rows are ever removed. The three counts are fixed keys, so an emptied
    # drawer goes to zero rather than disappearing.
    if ($p | get 0) == "row" {
        items row-off-args $settings ($p | get 1) ($p | get 2 | into int)
    } else { [] }
}

# The repaint, as DATA. Separated from `apply` so the tests can read exactly
# what would be sent without a bar being installed — the same trick `project`
# plays for the thinking.
export def message [changed: record, removed: record, settings: record]: nothing -> list<string> {
    let on = $changed | columns | where {|k| $k != "flash" }
        | each {|k| write-args $k ($changed | get $k) $settings } | flatten
    let off = $removed | columns | where {|k| $k != "flash" }
        | each {|k| erase-args $k $settings } | flatten
    # THE FLASH GOES LAST, because it is the only thing in a message that
    # animates and `--animate` colours every property set AFTER it in the same
    # message and none before (probed). Being last is what scopes the fade to
    # the chip and keeps it off a row that merely changed its label in the same
    # paint.
    let flash = if ("flash" in ($changed | columns)) {
        items flash-args $settings ($changed | get flash)
    } else if ("flash" in ($removed | columns)) {
        let was = $removed | get flash
        # The agent left the state before its window was out, so the
        # announcement is void: put it back and shut the drawer it opened.
        items unlit-args $settings $was.state $was.index --shut
    } else { [] }
    $on ++ $off ++ $flash
}

export def push-items [changed: record, removed: record, settings: record]: nothing -> nothing {
    let m = message $changed $removed $settings
    if ($m | is-not-empty) { ^$settings.binary ...$m | complete | ignore }
}

# ── installation ──────────────────────────────────────────────────────────────

export def install-message [settings: record]: nothing -> list<string> { items preallocate-args $settings }

export def install [settings: record]: nothing -> nothing {
    ^$settings.binary ...(install-message $settings) | complete | ignore
}

export def help-setup []: nothing -> string {
    let root = $SELF | path dirname | path dirname | path dirname
    ([ "Add one line to ~/.config/sketchybar/sketchybarrc, where you want the"
       "counters to sit among your other items:"
       ""
       $"  ($nu.current-exe) -n --no-std-lib -c 'use ($root); agent-notify displays install sketchybar'"
       ""
       "That creates the three counters, their drawers and their preview rows,"
       "then paints them from the session-store. No plugin script, no glyphs, no colours"
       "— they are all in agent-notify's own config file. Hovering a counter"
       "opens its drawer; hovering a row shows that agent's last message."
       ""
       "An agent that reports anything other than `working` also opens its own"
       "drawer for a few seconds, with its row lit. `flash_seconds: 0` turns"
       "that off; `flash_drawer: false` keeps the light and leaves the drawer"
       "shut."
       ""
       "A preview longer than the drawer scrolls: put the pointer anywhere in"
       "the drawer and use the wheel. `preview_depth` is how much of a message"
       "is kept within reach that way."
       ""
       "The periodic check that removes dead agents is NOT here: it is its own"
       "thing, so that turning the bar off cannot turn it off too."
       ""
       "  agent-notify prune-daemon help-setup launchd" ] | str join "\n")
}
