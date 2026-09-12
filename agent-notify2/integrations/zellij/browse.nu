# `agent-notify2 browse [query]` — the fleet as a list, and land in the one you
# pick.
#
# The terminal twin of the bar's drawers, and the other PULL half of the zellij
# integration: nothing dispatches to it, `surfaces:` does not turn it on, it runs
# because you ran it (plan.md D47). Its last line is `jump`.
#
# SKIM IS A HARD DEPENDENCY (D48), the same call `telescope` makes in its own
# picker. `input list` cannot draw a preview pane, and the preview is most of the
# point here: the rows say which agents exist, the pane says what the one under
# the cursor actually wants from you. A picker without it is a worse `store list`.
# So `require-picker` says so in as many words rather than letting `sk` fail as an
# unknown external command. There is no `$env.<module>_config.picker` hook any
# more, and nothing here reads a setting: what a row HOLDS is this file's
# business, and how the frame LOOKS is skim's.
#
# IT RUNS IN PLACE. v1's `browse` re-launched itself inside a `zellij run
# --floating` pane and needed a `--here` flag to not do that. The floating pane
# belongs to your keybinding — `agent-notify2 browse wiring` prints it — which is
# the same bargain as the one line in `sketchybarrc` and the eight in
# `settings.json`: we describe what to put in your config and never write it.
#
# AND IT DOES NOT PRUNE. A dead agent is the clock's business (core/clock.nu,
# every 30s). Pruning here too would be a second mechanism for one guarantee, and
# the worst it saves you from is a jump that says "no session called 'x'".

use ../../core/store.nu
use jump.nu

const SELF = path self

# Most urgent first, which is the only order a fleet list can be in. Idle sorts
# last rather than being hidden: an agent you have finished with is still one you
# may want to go back to.
const URGENCY = ["needs-attention" "awaiting" "working" "idle"]

# The same three shapes the pane titles and the bar wear — one vocabulary,
# learned once. Escapes, not literal characters: Private Use Area glyphs do not
# survive ordinary tooling (plan.md §10). Idle gets a space, so the column beside
# it still lines up.
const GLYPHS = {
    working: "\u{f021}"           # circular arrows — turning
    awaiting: "\u{f075}"          # speech bubble — talking to you
    needs-attention: "\u{f071}"   # warning triangle — stuck
    idle: " "
}

# ANSI NAMES, not hex. The bar picks its own colours because it sits on a
# desktop; a terminal has a theme, and this is the surface that should obey it.
def hue [state: string]: nothing -> string {
    match $state {
        "needs-attention" => (ansi light_red_bold)
        "awaiting" => (ansi yellow_bold)
        "working" => (ansi cyan)
        _ => (ansi dark_gray)
    }
}

# Checked at the entry point, and loudly, because every failure below this line
# is indistinguishable from pressing Esc.
def require-picker [] {
    if (plugin list | where name == "skim" | is-empty) {
        error make --unspanned {msg: ("agent-notify: browse needs nu_plugin_skim — "
            + "`plugin add ~/.cargo/bin/nu_plugin_skim` then `plugin use skim`")}
    }
}

# Where the preview goes and how wide its content may render.
#
# The preview is an agent's last MESSAGE — prose, often long. Rows are one line
# each and a fleet is rarely more than a handful, so on a wide terminal the
# message takes the side and keeps the full height; on a narrow one it goes
# underneath and takes the width instead, which is what prose wants more.
#
# The width is measured HERE and handed over, because the closure that uses it
# runs inside the plugin, which has no terminal to measure and would answer `term
# size`'s fallback of 80. Two columns come off so the widest line never lands on
# the pane's own edge.
const MIN_ROWS = 16
const WIDE_COLS = 120
const SIDE = 55   # % of a wide terminal the preview takes on the right
const UNDER = 65  # % of a narrow one it takes underneath

def pane []: nothing -> record<window: string, width: int> {
    let t = (term size)
    let beside = ($t.rows >= $MIN_ROWS and $t.columns >= $WIDE_COLS)
    let cols = if $beside { $t.columns * $SIDE // 100 } else { $t.columns }
    let window = if $t.rows < $MIN_ROWS {
        "down:0"
    } else if $beside {
        $"right:($SIDE)%:wrap"
    } else {
        $"down:($UNDER)%:wrap"
    }
    {window: $window, width: ([($cols - 2) 40] | math max)}
}

# Scrolling the preview. skim ships shift-up/shift-down for a line and the mouse
# wheel for whichever pane the pointer is over, but nothing page-wise — which is
# what a whole agent message wants.
#
# CTRL, not alt: zellij owns alt-h/j/k/l for pane focus and never forwards them.
# Its `normal` mode is `clear-defaults=true`, so every ctrl key does reach the
# pane. ctrl-d / ctrl-u page it the way they do in nvim.
#
# `--bind` REPLACES a default rather than layering over it, and both of these had
# one worth knowing about: ctrl-d was a second Abort (esc, ctrl-c and ctrl-g still
# are), and ctrl-u cleared the query (ctrl-w still rubs out a word).
const KEYS = {
    ctrl-down: "preview-down"
    ctrl-up: "preview-up"
    ctrl-d: "preview-page-down"
    ctrl-u: "preview-page-up"
}

def chars [s: string]: nothing -> int { $s | str length --grapheme-clusters }

# One line, no markup, for the tail of a row — and CAPPED. skim matches on the
# whole row, so carrying a few sentences of the message is what lets you find an
# agent by something it said; carrying the whole 4KB answer is a fuzzy matcher
# chewing through text it can never show, on every keystroke.
const GIST = 160

def gist [text: string]: nothing -> string {
    let one = $text | str replace --all --regex '\s+' " " | str trim
    if (chars $one) <= $GIST { return $one }
    ($one | split chars | first ($GIST - 1) | str join | str trim --right) + "…"
}

def rank [state: string]: nothing -> int {
    $URGENCY | enumerate | where item == $state | get -o 0.index | default ($URGENCY | length)
}

# How long it has been like this — the question a fleet list is really asking.
def since [stamp: any]: nothing -> string {
    if (($stamp | describe) != "string") { return "" }
    let then = try { $stamp | into datetime } catch { null }
    if ($then == null) { return "" }
    let d = (date now) - $then
    if $d < 1min { return "just now" }
    if $d < 1hr { return $"(($d / 1min) | math floor)m" }
    if $d < 1day { return $"(($d / 1hr) | math floor)h" }
    $"(($d / 1day) | math floor)d"
}

def where-of [rec: record]: nothing -> string {
    let z = $rec.zellij? | default {}
    let s = $z.session? | default ""
    if ($s | is-empty) { return "" }
    $"($s)/($z.tab_base? | default ($z.tab_id? | default '?'))"
}

def label-of [rec: record]: nothing -> string {
    let name = $rec.name? | default ""
    if ($name | is-not-empty) { return $name }
    let dir = $rec.cwd? | default "" | path basename
    if ($dir | is-not-empty) { $dir } else { $rec.id | str substring 0..7 }
}

# The rows, most urgent first, in four columns the eye can run down: what state,
# which agent, where it lives, and what it last said. The first three are padded
# to a common width; the message takes what is left and is dimmed, because it is
# context rather than the thing you are choosing between.
#
# `row` is what skim SHOWS and, with the colours stripped, what it MATCHES — so a
# state, a directory or a phrase from a message all narrow the list. `rec` rides
# along so the choice maps straight back to its record with no second lookup.
export def rows [recs: list<record>]: nothing -> list<record> {
    let cells = $recs
        | each {|r| {
            state: ($r.state? | default "idle")
            label: (label-of $r)
            place: (where-of $r)
            gist: (gist ($r.message? | default ""))
            rec: $r
        }}
        | sort-by {|c| rank $c.state } {|c| $c.place } {|c| $c.label }
    let w_state = $cells | each {|c| chars $c.state } | append 0 | math max
    let w_label = $cells | each {|c| chars $c.label } | append 0 | math max
    let w_place = $cells | each {|c| chars $c.place } | append 0 | math max

    $cells | each {|c|
        let mark = $GLYPHS | get -o $c.state | default " "
        let head = $"(hue $c.state)($mark) ($c.state | fill --width $w_state)(ansi reset)"
        let mid = $"($c.label | fill --width $w_label)  (ansi dark_gray)($c.place | fill --width $w_place)(ansi reset)"
        {row: $"($head)  ($mid)  (ansi dark_gray)($c.gist)(ansi reset)", rec: $c.rec}
    }
}

# bat, or the text it was given. No `--theme`: bat reads ~/.config/bat/config even
# when it is not on a terminal, so the palette lives in exactly one place.
# Wrapping is off because the preview pane wraps on word boundaries and bat breaks
# mid-word.
def styled [text: string]: nothing -> string {
    let r = try {
        $text | ^bat --color=always --paging=never --style=plain --wrap never --language md | complete
    } catch { null }
    if ($r == null) or ($r.exit_code != 0) or (($r.stdout | str trim) | is-empty) { return $text }
    $r.stdout
}

# What the pane shows for the agent under the cursor: who it is, how long it has
# been like this, where it lives, and then its last message VERBATIM — the
# markdown the agent actually wrote.
#
# Styling it is a bonus, not a dependency: anything unexpected from `bat` falls
# back to the source, which is what an unstyled preview has always been.
export def preview [rec: record, width: int]: nothing -> string {
    let state = $rec.state? | default "idle"
    let ago = since ($rec.state_since? | default null)
    let when = if ($ago | is-empty) { "" } else { $" for ($ago)" }
    let head = $"(hue $state)(label-of $rec)(ansi reset)  (ansi dark_gray)($state)($when)(ansi reset)"
    let place = [(where-of $rec) ($rec.cwd? | default "")] | where {|x| $x | is-not-empty } | str join "  ·  "
    let body = $rec.message? | default "" | str trim
    let shown = if ($body | is-empty) { $"(ansi dark_gray)— no message —(ansi reset)" } else { styled $body }
    [$head $"(ansi dark_gray)($place)(ansi reset)" "" $shown] | str join "\n"
}

# Pick an agent and go there. `query` prefills the filter, which leaves you in the
# list with a count and a backspace rather than staring at an error.
#
# Esc, ctrl-c and ctrl-g all abort, and skim reports that as a failure — so a
# cancel and a crash arrive the same way. `require-picker` runs first for exactly
# that reason: a missing plugin would otherwise be swallowed as "you changed your
# mind".
@search-terms agent notify browse pick picker choose list agents fleet fuzzy
@example "choose an agent and land in its pane" { agent-notify2 browse }
@example "…starting from a filter" { agent-notify2 browse zz }
export def main [
    query?: string      # prefills skim's filter
] {
    require-picker
    let all = rows (store list)
    if ($all | is-empty) {
        print $"(ansi dark_gray)no agents(ansi reset)"
        return
    }

    let p = (pane)
    # Wrapped to hand the closure the two things it cannot find out for itself:
    # the pane's width, and that there is a terminal at the far end of this at
    # all. `use_ansi_coloring: auto` reads as "no" in here — this runs inside the
    # plugin, with nothing attached — and a coloured preview would arrive grey.
    let render = {||
        let it = $in
        $env.config.use_ansi_coloring = true
        preview $it.rec $p.width
    }
    let picked = try {
        $all | sk --format {|| $in.row } --preview $render --preview-window $p.window --bind $KEYS --layout reverse --prompt "agent " --query ($query | default "")
    } catch { null }
    if ($picked == null) { return }
    jump $picked.rec.id
}

# What to put in your zellij config so Alt-a opens this. Printed, never applied
# (D20): the floating pane is zellij's to make, and the keybinding is yours.
@search-terms agent notify browse wiring keybinding zellij config alt-a floating
@example "how do I bind this?" { agent-notify2 browse wiring }
export def wiring []: nothing -> string {
    let root = $SELF | path dirname | path dirname | path dirname
    let skim = which "nu_plugin_skim" | get -o 0.path | default "~/.cargo/bin/nu_plugin_skim"
    let palette = $"source ($nu.home-dir | path join '.config' 'nushell' 'skim-colors.nu')"
    ([ "Add this to the `normal` mode of ~/.config/zellij/config.kdl:"
       ""
       "  bind \"Alt a\" {"
       $"      Run \"nu\" \"-n\" \"--plugins\" \"($skim)\" \"-c\" \\"
       $"          \"($palette); use ($root); agent-notify2 browse\" {"
       "          name \"agents\""
       "          floating true"
       "          close_on_exit true"
       "          width \"90%\"; height \"90%\"; x \"5%\"; y \"5%\""
       "      }"
       "      SwitchToMode \"Normal\""
       "  }"
       ""
       "`-n` starts nu with no config, so the plugin registry is empty and skim"
       "has to be handed over by path."
       ""
       "The `source` is SKIM's palette, not ours — it sets $env.SKIM_DEFAULT_OPTIONS,"
       "which `-n` would otherwise leave unset and the picker would open in skim's"
       "default colours. Drop it if you have no such file. Nothing else is needed:"
       "this module reads no settings for the picker, and the floating pane is"
       "zellij's to make, not ours." ] | str join "\n")
}
