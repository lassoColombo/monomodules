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
#
# THE FLASH is the second generated shell in this file and the only one that is
# not a reaction to the mouse — see `expiry-shell`, which is where the one timer
# on the bar lives and where all three ways a flash can end are spelled out.

# The three states worth a counter, in the order they are added to the bar. Idle
# is not one: an agent with nothing to say does not deserve a number.
export const COUNTED = ["working" "awaiting" "needs-attention"]

# The states that ANNOUNCE THEMSELVES — everything an agent reports that is not
# "still going". `working` is deliberately not one: an agent getting on with it
# is the state the bar is in most of the day, and a bar that lit up for it would
# be lit up all day and mean nothing.
export const ANNOUNCED = ["awaiting" "needs-attention"]

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

# The item that holds a flash: a hidden one, whose whole content is the moment
# the flash is over and what to do then. It draws nothing ever.
export def flash-item [settings: record]: nothing -> string { $"($settings.prefix)flash" }

# What the pointer says when it arrives: the announcement has been read. Its own
# event rather than a shared one, so a bar full of other people's items cannot
# be listening and cannot be woken.
export def seen-event [settings: record]: nothing -> string { $"($settings.prefix)flash_seen" }

# The footer's scroll. `scroll-item` is where the window's position lives, in
# its own icon (see `register`); `scrolled-event` is how a wheel anywhere in a
# drawer reaches it, since a mouse event goes only to the item under the pointer
# and that item is a different one every time.
export def scroll-item [settings: record]: nothing -> string { $"($settings.prefix)scroll" }
export def scrolled-event [settings: record]: nothing -> string { $"($settings.prefix)scrolled" }

# The line under the footer that says how much is still below it. A drawer whose
# preview fits says nothing at all.
export def more-name [settings: record, state: string]: nothing -> string { $"(item-name $settings $state).more" }

# Same hue, less alpha: a counter at zero stays recognisable by colour instead
# of going grey, so the three icons read at a glance the way the wifi and
# battery widgets do.
export def tint [color: string, alpha: string]: nothing -> string {
    $"0x($alpha)($color | str substring 4..)"
}

# HOW LOUD A LIT THING IS. A wash and an edge, not a block of colour: a chip and
# a row both have to stay readable while they are lit, and it is the border that
# actually catches the eye — a filled pill just looks like a different theme.
const LIT_FILL = "33"
const LIT_EDGE = "aa"
const UNLIT = "0x00000000"

# Animation ticks, at 60 a second (probed). In long enough to read as something
# arriving rather than as a repaint; out slower than in, because a thing leaving
# should not be the part that catches your eye.
const FADE_IN = 18
const FADE_OUT = 30

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
#
# AND IT TELLS THE FLASH IT HAS BEEN SEEN. `--trigger` is one token on a message
# that was being sent anyway, and it is what stops a flash shutting a drawer
# under a pointer that came to read it — see `expiry-shell`.
export def open-shell [settings: record, state: string, count: int]: nothing -> string {
    let seen = ["--trigger" (seen-event $settings)]
    if $count == 0 { return ($GUARD + (close-shell $settings) + $" ($seen | str join ' ')") }
    let others = $COUNTED | where {|st| $st != $state }
        | each {|st| ["--set" (item-name $settings $st) "popup.drawing=off"] } | flatten
    # The WHOLE footer, not just the screenful it shows — what is held below is
    # still on the item, and a drawer that reopened onto row 20 of the last
    # agent you read would be a mystery. Blanking it also puts the scroll back
    # to nothing held, so a wheel over an empty footer does nothing at all.
    let blank = 0..$settings.preview_depth
        | each {|index| ["--set" (pv-name $settings $state $index) "drawing=off"] } | flatten
    let rewound = ["--set" (scroll-item $settings) $"icon=(register $settings $state 0 0)"
                   "--set" (more-name $settings $state) "drawing=off"]
    let args = ["--set" (item-name $settings $state) "popup.drawing=on"] ++ $others ++ $blank ++ $rewound ++ $seen
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

# ── the footer, and scrolling it ──────────────────────────────────────────────
#
# THE FOOTER HOLDS MORE THAN IT SHOWS. `preview_depth` rows are written to the
# bar by the paint; `preview_lines - 1` of them are switched on, starting under
# the WHERE line, and the rest sit there switched off. So SCROLLING MOVES NO
# TEXT — it is `drawing=on` and `drawing=off` over slots that already say the
# right thing, which is why a wheel never touches the agent's words and nothing
# about it has to be quoted or escaped.
#
# WHERE THE POSITION LIVES. One hidden item's icon, as `pv:<item>:<held>:<top>`:
# which drawer's footer is filled, how many body rows it holds, and which one is
# at the top of the window. A script gets `$SENDER`, `$NAME`, `$BUTTON` and
# `$SCROLL_DELTA` from SketchyBar and nothing else, so a property is the only
# place a scroll can leave something for the next scroll — and one `--query` to
# read it back is 4.3ms against a wheel that is throttled to about seven events
# a second (probed), so it is affordable where a nushell would not be.
#
# WHY AN EVENT IN THE MIDDLE. A mouse event goes ONLY to the item under the
# pointer, and that item is a different row every time — so every row and every
# footer line forwards one `--trigger`, and the thinking lives once, on the item
# that holds the position.

# The position, as the one string that is written and read back. `pv:` is an
# anchor rather than decoration: the reader finds it by that prefix, so it does
# not depend on where SketchyBar happens to put `icon` in its JSON.
def register [settings: record, state: string, held: int, top: int]: nothing -> string {
    ["pv" (item-name $settings $state) ($held | into string) ($top | into string)] | str join ":"
}

# How far one notch moves, from the momentum SketchyBar reports: deltas came
# back between 7 and 162 on a real trackpad, so this gives one row for a nudge
# and five for a shove. A fixed step would make a long message take a minute at
# seven events a second.
const MOMENTUM = 40

# A wheel, passed on. Every row and every footer line carries this, because a
# mouse event reaches ONLY the item under the pointer and that item is a
# different one every time — the thinking lives once, on the item that holds
# the position.
def forward-shell [settings: record]: nothing -> string {
    $"[ \"$SENDER\" = mouse.scrolled ] && exec ($settings.binary) --trigger (scrolled-event $settings) SCROLL_DELTA=$SCROLL_DELTA"
}

# THE WHOLE OF SCROLLING, in one static script written once at install — there
# is nothing per-paint in it, because the paint already put the text on the bar
# and this only decides which rows are drawn.
#
# It reads the position out of its own icon, works out the new top from the
# momentum, and sends ONLY THE SLOTS THAT CHANGE: two for a nudge, ten for a
# shove, never the whole footer. Everything it computes is a number, so the
# message it builds cannot contain anything an agent wrote.
#
# A NEGATIVE DELTA GOES DOWN the message — that is the `case` below, and
# inverting the wheel is the one pattern in it.
def scroll-shell [settings: record]: nothing -> string {
    let sb = $settings.binary
    let reg = scroll-item $settings
    [ $"[ \"$SENDER\" = (scrolled-event $settings) ] || exit 0"
      $"q=$\(($sb) --query ($reg)\)"
      "r=${q#*'\"pv:'}"
      "[ \"$r\" = \"$q\" ] && exit 0"
      "r=${r%%'\"'*}"
      "t=${r%%:*}; r=${r#*:}; n=${r%%:*}; p=${r#*:}"
      $"w=($settings.preview_lines - 1)"
      "[ \"$n\" -gt \"$w\" ] || exit 0"
      "d=${SCROLL_DELTA:-0}"
      "[ \"$d\" -eq 0 ] && exit 0"
      "m=${d#-}"
      $"s=$\(\(m / ($MOMENTUM) + 1\)\)"
      "case \"$d\" in -*) k=$((p+s)) ;; *) k=$((p-s)) ;; esac"
      "x=$((n-w))"
      "[ \"$k\" -lt 0 ] && k=0"
      "[ \"$k\" -gt \"$x\" ] && k=$x"
      "[ \"$k\" -eq \"$p\" ] && exit 0"
      "a=\"\"; i=1"
      ("while [ \"$i\" -le \"$n\" ]; do o=0; v=0;"
       + " if [ \"$i\" -gt \"$p\" ] && [ \"$i\" -le $((p+w)) ]; then o=1; fi;"
       + " if [ \"$i\" -gt \"$k\" ] && [ \"$i\" -le $((k+w)) ]; then v=1; fi;"
       + " if [ \"$o\" -ne \"$v\" ]; then"
       + " if [ \"$v\" -eq 1 ]; then a=\"$a --set $t.pv.$i drawing=on\";"
       + " else a=\"$a --set $t.pv.$i drawing=off\"; fi; fi;"
       + " i=$((i+1)); done")
      "b=$((n-k-w)); c=on"
      "[ \"$b\" -le 0 ] && c=off"
      $"exec ($sb) $a --set $t.more label=$b drawing=$c --set ($reg) icon=pv:$t:$n:$k" ]
    | str join "; "
}

# WHAT EACH PREVIEW SLOT SHOULD SAY, decided once and rendered twice. A hover
# has it baked into a shell command; a flash sends it as plain argv, having
# opened the drawer with nobody's pointer in it. The two differ only in
# quoting — and quoting is the one thing that must live where the quote is
# written, so the decision is here and neither rendering repeats it.
def pv-slots [settings: record, state: string, rows: list<record>]: nothing -> list<record> {
    let hue = $settings.colors | get $state
    let window = $settings.preview_lines - 1
    0..$settings.preview_depth | each {|index|
        let r = $rows | get -o $index
        let name = pv-name $settings $state $index
        # FILLED AND SHOWN ARE NOT THE SAME QUESTION, and conflating them is
        # what made a scroll reveal blank rows: every line the agent wrote is
        # WRITTEN, and only the first screenful is DRAWN. Slot 0 is the WHERE
        # line and never scrolls; a paint always leaves the window at the top.
        if $r == null { {name: $name, filled: false} } else {
            {name: $name, filled: true, on: ($index <= $window), label: $r.t, color: (ink $settings $hue $r.k)}
        }
    }
}

# What a filled footer needs besides its words: where its window is, and how far
# under it the rest goes. NUMBERS AND ITEM NAMES ONLY — no agent text — which is
# what lets one builder serve the hover, the flash and the scroll alike, and
# what keeps a wheel from ever having to quote anything.
export def pv-tail [settings: record, state: string, rows: list<record>]: nothing -> list<string> {
    let held = [(($rows | length) - 1) $settings.preview_depth] | math min
    let rest = $held - ($settings.preview_lines - 1)
    let more = more-name $settings $state
    let below = if $rest <= 0 { ["--set" $more "drawing=off"] } else {
        ["--set" $more $"label=($rest)" "drawing=on"]
    }
    ["--set" (scroll-item $settings) $"icon=(register $settings $state $held 0)"] ++ $below
}

# The preview as ARGV — no shell between us and the bar, so the agent's words go
# through exactly as written.
export def pv-args [settings: record, state: string, rows: list<record>]: nothing -> list<string> {
    let slots = pv-slots $settings $state $rows | each {|s|
        if $s.filled {
            ["--set" $s.name $"label=($s.label)" $"label.color=($s.color)"
             $"drawing=(if $s.on { 'on' } else { 'off' })"]
        } else { ["--set" $s.name "drawing=off"] }
    } | flatten
    $slots ++ (pv-tail $settings $state $rows)
}

# One row's preview, as the command that will show it. Called at PAINT time with
# the rows already wrapped and kinded, so the hover itself does no thinking —
# and it tells the flash it has been seen for the same reason `open-shell` does:
# a pointer can reach a row without ever crossing the counter above it.
#
# A ROW IS ALSO WHERE A WHEEL LANDS, because you scroll the preview of the agent
# you are pointing at, not the one you walked your pointer down to. So the
# forward comes first and the hover's own guard after it.
export def hover-shell [settings: record, state: string, rows: list<record>]: nothing -> string {
    let slots = pv-slots $settings $state $rows | each {|s|
        if $s.filled {
            ["--set" $s.name $"'label=(quotable $s.label)'" $"label.color=($s.color)"
             $"drawing=(if $s.on { 'on' } else { 'off' })"]
        } else { ["--set" $s.name "drawing=off"] }
    } | flatten
    let args = $slots ++ (pv-tail $settings $state $rows) ++ ["--trigger" (seen-event $settings)]
    (forward-shell $settings) + "; " + $GUARD + $"($settings.binary) ($args | str join ' ')"
}

# ── the shell a CLICK runs ────────────────────────────────────────────────────
#
# Where `cli/jump.nu` is, worked out from where this file is. Baked as an
# ABSOLUTE path into every click script, because the bar daemon's working
# directory is not ours and its PATH is launchd's.
const JUMP_MODULE = (path self | path dirname | path dirname | path dirname | path join "cli" "jump.nu")

# A CLICK RUNS THE MODULE; IT DOES NOT GET A BAKED ARGV (plan.md D76). That is
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

# ── the flash ─────────────────────────────────────────────────────────────────
#
# A drawer that opens itself. An agent that says something other than "still
# going" gets its chip lit, its drawer opened on its own words, and its row lit
# inside it — and then, a few seconds later, all of that taken away again.
#
# THE HARD PART IS THE TAKING AWAY, because this module has no daemon. Three
# things can end a flash and they all land in `unlit-args`:
#
#   the clock    the one timer on the bar. Armed by the raise, it ticks once a
#                second and does nothing until the moment baked into its script
#   the pointer  `<prefix>flash_seen`, triggered by every hover of ours
#   the next paint
#                the agent left the state, so `flash` arrives in `removed` and
#                the undo is sent on the spot
#
# CANCELLATION IS STRUCTURAL, which is the part worth keeping. There is ONE
# timer item and raising a flash REWRITES ITS SCRIPT, so an older announcement's
# deadline cannot cut a newer one short and there is no generation counter
# anywhere to say so. The deadline itself is `state_since` plus the window — a
# fact about the record, not `now` plus the window — so it does not drift when
# an unrelated paint re-sends it.
#
# WHAT IT COSTS when nothing is happening: nothing. `update_freq=0` is not a
# slow tick, it is no tick at all (probed), and a disarmed flash item has an
# empty script, so the `--trigger` every hover sends runs no shell.

# Everything one flash lit, put back, and the timer that would have done it
# disarmed. Built at RAISE time because that is when what got lit is known: the
# same list is sent on the spot when an agent leaves the state, and baked into
# the timer's script for when nothing else is ever going to happen.
#
# `--shut` closes the drawer the flash opened as well, and ONLY the clock uses
# it. A pointer that has arrived owns the drawer from that moment, and nothing
# of ours may shut one under a pointer that came to read it.
export def unlit-args [settings: record, state: string, index: any, --shut]: nothing -> list<string> {
    let item = item-name $settings $state
    let row = if $index == null { [] } else {
        ["--set" (row-name $settings $state $index)
         $"background.color=($settings.colors.row)" "background.border_width=0"]
    }
    let drawer = if $shut { ["--set" $item "popup.drawing=off"] } else { [] }
    let timer = ["--set" (flash-item $settings) "update_freq=0" "script="]
    # The chip last, and behind the fade, because `--animate` colours everything
    # after it in a message and nothing else here wants interpolating (probed).
    let chip = ["--animate" "sin" ($FADE_OUT | into string)
                "--set" $item $"background.color=($UNLIT)" "background.border_width=0"]
    $timer ++ $row ++ $drawer ++ $chip
}

# The timer's whole mind, in four commands. Two senders reach it and they want
# different things, so the first line is `&& exec` rather than a guard: a
# pointer that said seen leaves by it, and anything else falls through to the
# deadline. Nothing in here needs quoting — the agent's words are not in it.
def expiry-shell [settings: record, value: record]: nothing -> string {
    let quiet = $"($settings.binary) (unlit-args $settings $value.state $value.index | str join ' ')"
    let over = $"($settings.binary) (unlit-args $settings $value.state $value.index --shut | str join ' ')"
    [ $"[ \"$SENDER\" = (seen-event $settings) ] && exec ($quiet)"
      "[ \"$SENDER\" = routine ] || exit 0"
      $"[ \"$\(date +%s\)\" -ge ($value.until) ] || exit 0"
      $"exec ($over)" ] | str join "; "
}

# Raise it. The ROW is not lit here — it is lit by its own key, because only the
# diff knows which row STOPPED being the lit one when an agent's slot moves
# under it. What is lit here is the chip, which belongs to no row and would
# otherwise have nobody to switch it off.
export def flash-args [settings: record, value: record]: nothing -> list<string> {
    let item = item-name $settings $value.state
    let hue = $settings.colors | get $value.state
    let drawer = if not $settings.flash_drawer { [] } else {
        let others = $COUNTED | where {|st| $st != $value.state }
            | each {|st| ["--set" (item-name $settings $st) "popup.drawing=off"] } | flatten
        let preview = pv-args $settings $value.state $value.lines
        ["--set" $item "popup.drawing=on"] ++ $others ++ $preview
    }
    let timer = ["--set" (flash-item $settings) "update_freq=1" $"script=(expiry-shell $settings $value)"]
    let chip = ["--animate" "sin" ($FADE_IN | into string)
                "--set" $item $"background.color=(tint $hue $LIT_FILL)"
                $"background.border_color=(tint $hue $LIT_EDGE)" "background.border_width=1"]
    $drawer ++ $timer ++ $chip
}

# ── what a paint writes ───────────────────────────────────────────────────────

# A drawer's size changed: the counter's number, its header, the script behind
# it — since an empty drawer opens nothing — and WHERE CLICKING IT GOES.
#
# A COUNTER IS A THING YOU CLICK, AND SOMETIMES THERE IS A CORRECT ANSWER. When
# it stands for exactly one agent, that agent is unambiguously what you meant,
# so the click jumps straight there rather than opening a drawer to show you a
# list of one. When it stands for none or for several there is no correct
# session, so the click does what it always did and shuts the drawers. Hovering
# is unchanged either way — the drawer is still how you choose among several.
export def counter-args [settings: record, state: string, value: record]: nothing -> list<string> {
    let item = item-name $settings $state
    let hue = $settings.colors | get $state
    let count = $value.n
    let only = $value.only? | default ""
    let label = if $count == 0 { "  All clear"
        } else if $count > $settings.rows { $"  ($count) active · ($settings.rows) shown"
        } else { $"  ($count) active" }
    [ "--set" $item
      $"icon.color=(if $count > 0 { $hue } else { (tint $hue '66') })"
      $"label=($count)"
      $"label.color=(if $count > 0 { $hue } else { $settings.colors.dim })"
      $"script=(open-shell $settings $state $count)"
      $"click_script=(if ($only | is-empty) { (close-shell $settings) } else { (click-shell $settings $only) })"
      "--set" (head $settings $state)
      $"icon=(if $count == 0 { '✓' } else { '' })"
      $"icon.color=(if $count == 0 { $settings.colors.working } else { $settings.colors.dim })"
      $"label=($label)" ]
}

# One agent's row: what it says, whether it is the one that just arrived, what
# hovering it shows, and where clicking it takes you.
#
# THE PILL IS A DIFFED FACT, not something the flash reaches in and sets. A
# flashing agent's row moves when an older one leaves the state, and the diff is
# the only thing that knows both slots — so `flash` rides in the row's own value
# and the row that stopped being lit is unlit by the same mechanism that lights
# the new one.
export def row-args [settings: record, state: string, index: int, value: record]: nothing -> list<string> {
    let hue = $settings.colors | get $state
    let lit = $value.flash? | default false
    [ "--set" (row-name $settings $state $index)
      $"label=($value.label)"
      "drawing=on"
      $"background.color=(if $lit { (tint $hue $LIT_FILL) } else { $settings.colors.row })"
      $"background.border_color=(if $lit { (tint $hue $LIT_EDGE) } else { $UNLIT })"
      $"background.border_width=(if $lit { 1 } else { 0 })"
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
    # The pointer's way of saying it has seen a flash. Declared before anything
    # subscribes to it, and declaring it twice is not an error (probed), so a
    # re-run of the install is still idempotent.
    mut args = ["--add" "event" (seen-event $settings) "--add" "event" (scrolled-event $settings)]
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
            # The chip's pill, present and invisible, so a flash has something
            # to fade IN — an animation needs a value to come from, and a
            # background that is switched off has none. Height and corner radius
            # are left to the bar's own `--default`, which is where the bracket
            # around these three already gets its shape: a chip that lights up
            # must be the same pill as the group it sits in.
            "background.drawing=on" $"background.color=($UNLIT)" "background.border_width=0"
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
                # `entered` only — leaving a row is how you reach the footer it
                # filled, so hiding on `exited` made the text vanish exactly as
                # you went to read it — plus the wheel, because the preview you
                # want to scroll is the one belonging to the row you are on.
                "--subscribe" $slot "mouse.entered" "mouse.scrolled"
            ]
        }
        # `preview_depth` body slots BELOW the WHERE line, not one screenful:
        # what a paint cannot fit is written here too and left switched off, and
        # that is the whole of what a scroll moves over.
        for index in 0..$settings.preview_depth {
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
                # A footer line is where a wheel most often lands, so it
                # forwards one. Static: it says nothing about which drawer or
                # what is in it — the item that holds the position knows both.
                $"script=(forward-shell $settings)"
                "--subscribe" $slot "mouse.scrolled"
            ]
        }
        # How much is still below the window. Drawn only when there IS more,
        # because a drawer whose preview fits should say nothing — and it is the
        # only thing that tells you the footer scrolls at all.
        let more = more-name $settings $state
        $args = $args ++ [
            "--add" "item" $more $"popup.($item)"
            "--set" $more "drawing=off" "icon=▾"
            $"icon.color=(tint $hue '99')"
            $"icon.font=($settings.font):Bold:10.0"
            $"label.color=($settings.colors.dim)"
            $"label.font=($settings.font):Bold:10.0"
            "icon.padding_left=14" "label.padding_right=14" "label.padding_left=4"
            "background.drawing=off"
            $"script=(forward-shell $settings)"
            "--subscribe" $more "mouse.scrolled"
        ]
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
    # THE ONE TIMER ON THE BAR, and it arrives disarmed and empty. It holds a
    # flash's deadline and nothing else; liveness is still not a display's job
    # and never was (core/prune-daemon/). A flash writes both properties when it
    # raises one and puts them back when it is over, so between flashes this
    # item costs the bar nothing at all.
    let flash = flash-item $settings
    $args = $args ++ [
        "--add" "item" $flash $settings.position
        "--set" $flash "drawing=off" "update_freq=0" "script="
        "--subscribe" $flash (seen-event $settings)
    ]
    # Where the footer's window position lives, and the only item that moves it.
    # Its script is STATIC — no paint ever rewrites it — because scrolling is
    # `drawing` over slots a paint already filled, and the position it needs is
    # in its own icon.
    let scroll = scroll-item $settings
    $args = $args ++ [
        "--add" "item" $scroll $settings.position
        "--set" $scroll "drawing=off" "icon=" $"script=(scroll-shell $settings)"
        "--subscribe" $scroll (scrolled-event $settings)
    ]
    let names = $COUNTED | each {|state| item-name $settings $state }
    $args ++ ["--add" "bracket" (group $settings) ...$names
              "--set" (group $settings) "background.drawing=on" $"background.color=($settings.background)"]
}
