# SketchyBar: three counters — how many agents are working, how many are waiting
# for you, how many are stuck.
#
#      2      3      1
#
# WHAT THIS COSTS, measured, because the numbers chose the design:
#
#   sketchybar --query bar (a round trip)     5.98ms
#   --set ONE property                        6.59ms
#   --set TEN properties in ONE message       6.54ms    ← batching is free
#   --add + --remove one item                17.51ms
#
# Two conclusions. A message costs what a process costs and almost nothing per
# property, so a whole repaint is ONE call. And adding or removing items is about
# three times the price of setting them, so the item pool is created once by
# `install` and never touched again — v1 learned that the expensive way, by
# rebuilding ~43 items per paint and pinning the daemon near 40% CPU, which is
# what used to make bar clicks lag.
#
# HOW THIS DIFFERS FROM v1, and it is most of the file that is missing. v1 painted
# like this:
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
# AND v1's CACHE IS GONE. It wrote its model to disk after each paint so an
# unchanged bar could send nothing. The gate in core/dispatch.nu answers the same
# question by running `project` twice, and stores nothing at all. The gate bites
# harder here than for zellij, too: a counter shows only a NUMBER, so a new
# message, a directory change, or a re-asserted state all project identically and
# never reach the bar.

use ../core/schema.nu

const SELF = path self

export const INFO = {name: "sketchybar", title: "SketchyBar agent counters"}

# The three states worth a counter, in the order they are added to the bar. Idle
# is not one: an agent with nothing to say does not deserve a number.
const COUNTED = ["working" "awaiting" "needs-attention"]

# Escapes, not literal characters — Private Use Area glyphs do not survive
# ordinary tooling (plan.md §10). The same three shapes the zellij titles use,
# deliberately: one vocabulary, learned once. Duplicated rather than shared so
# that each surface stays a leaf of the import tree (§10), and because a bar can
# colour a glyph where a pane title cannot.
const GLYPHS = {
    working: "\u{f021}"           # circular arrows — turning
    awaiting: "\u{f075}"          # speech bubble — talking to you
    needs-attention: "\u{f071}"   # warning triangle — stuck
}

# Rosé Pine, to match the rest of the bar. `dim` is the colour a zero wears.
const DEFAULTS = {
    prefix: "an_"
    position: "left"
    font: "MesloLGLDZ Nerd Font"
    background: "0xff26233a"
    colors: {
        working: "0xff9ccfd8"          # foam
        awaiting: "0xfff6c177"         # gold
        needs-attention: "0xffeb6f92"  # love
        dim: "0xff6e6a86"              # muted
    }
}

def item-suffix [state: string]: nothing -> string {
    if $state == "needs-attention" { "attention" } else { $state }
}

# Same hue, less alpha: a counter at zero stays recognisable by colour instead of
# going grey, so the three icons read at a glance the way the wifi and battery
# widgets do.
def tint [color: string, alpha: string]: nothing -> string {
    $"0x($alpha)($color | str substring 4..)"
}

export def settings [given: record, me: any]: nothing -> record {
    for k in ($given | columns | where {|k| $k not-in ($DEFAULTS | columns) }) {
        error make --unspanned {msg: $"sketchybar: '($k)' is not a setting \(try: ($DEFAULTS | columns | str join ', ')\)"}
    }
    let colors = $given.colors? | default {}
    if not (($colors | describe) | str starts-with "record") {
        error make --unspanned {msg: $"sketchybar: `colors` must be a map, got ($colors | describe)"}
    }
    let known = ($schema.STATES | append "dim")
    for k in ($colors | columns) {
        if ($k not-in $known) {
            error make --unspanned {msg: $"sketchybar: '($k)' is not a colour we use \(try: ($known | str join ', ')\)"}
        }
        let v = $colors | get $k
        if (($v | describe) != "string") or (not ($v =~ '^0x[0-9a-fA-F]{8}$')) {
            error make --unspanned {msg: $"sketchybar: the colour for '($k)' must look like 0xAARRGGBB, got ($v | to nuon)"}
        }
    }
    $DEFAULTS | merge ($given | reject --optional colors) | upsert colors ($DEFAULTS.colors | merge $colors)
}

# PURE, and deliberately tiny: three numbers. Everything else about an agent —
# its name, its message, where it lives — is invisible here, which is exactly why
# the gate stops so much work before it starts.
export def project [records: list<record>, settings: record]: nothing -> record {
    $COUNTED | reduce --fold {} {|state, acc|
        $acc | merge {($state): ($records | where {|r| ($r.state? | default "idle") == $state } | length)}
    }
}

# The repaint, as DATA. Separated from `apply` so the tests can read exactly what
# would be sent without a bar being installed — the same trick `project` plays for
# the thinking, applied to the side effect.
export def message [desired: record, settings: record]: nothing -> list<string> {
    $COUNTED | each {|state|
        let n = $desired | get -o $state | default 0
        let item = $"($settings.prefix)(item-suffix $state)"
        let hue = $settings.colors | get $state
        [ "--set" $item
          $"icon.color=(if $n > 0 { $hue } else { (tint $hue '66') })"
          $"label=($n)"
          $"label.color=(if $n > 0 { $hue } else { $settings.colors.dim })" ]
    } | flatten
}

export def apply [desired: record, settings: record]: nothing -> any {
    let m = message $desired $settings
    if ($m | is-not-empty) { try { ^sketchybar ...$m | complete | ignore } }
    null   # nothing learned; the bar tells us nothing we did not already know
}

# ── installation ─────────────────────────────────────────────────────────────
# The item pool, created ONCE. Also as data first, for the same reason.
#
# The hidden `tick` item is the backstop and the janitor in one line: `surfaces
# refresh` prunes agents that are provably gone before it repaints, so a killed
# agent disappears from the bar within 30 seconds without any hook being involved.
export def install-message [s: record]: nothing -> list<string> {
    let counters = $COUNTED | each {|state|
        let item = $"($s.prefix)(item-suffix $state)"
        [ "--add" "item" $item $s.position
          "--set" $item
          $"icon=($GLYPHS | get $state)"
          $"icon.font=($s.font):Bold:15.0"
          $"icon.color=(tint ($s.colors | get $state) '66')"
          "label=0"
          $"label.font=($s.font):Semibold:13.0"
          $"label.color=($s.colors.dim)" ]
    } | flatten

    let names = $COUNTED | each {|state| $"($s.prefix)(item-suffix $state)" }
    let group = $"($s.prefix)group"
    let tick = $"($s.prefix)tick"

    ($counters
     ++ ["--add" "bracket" $group ...$names
         "--set" $group "background.drawing=on" $"background.color=($s.background)"]
     ++ ["--add" "item" $tick $s.position
         "--set" $tick "drawing=off" "update_freq=30" $"script=(tick-command)"])
}

def tick-command []: nothing -> string {
    let root = $SELF | path dirname | path dirname
    $"($nu.current-exe) -n --no-std-lib -c 'use ($root); agent-notify2 surfaces refresh'"
}

export def install [s: record]: nothing -> nothing {
    ^sketchybar ...(install-message $s) | complete | ignore
}

export def wiring []: nothing -> string {
    let root = $SELF | path dirname | path dirname
    ([ "Add one line to ~/.config/sketchybar/sketchybarrc, where you want the"
       "counters to sit among your other items:"
       ""
       $"  ($nu.current-exe) -n --no-std-lib -c 'use ($root); agent-notify2 surfaces install sketchybar'"
       ""
       "That creates the three counters, their bracket, and one hidden 30s item"
       "that prunes dead agents and repaints. Nothing else belongs in your bar's"
       "config: no plugin script, no glyphs, no colours — they are all in"
       "agent-notify's own config file." ] | str join "\n")
}
