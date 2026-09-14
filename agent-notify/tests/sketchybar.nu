# Step 5 — the SketchyBar counters, their drawers, and the hover preview.
#
# Not one subprocess runs in this suite, and no bar has to be installed. That is
# on purpose: the display splits the SIDE EFFECT into a pure `message` builder
# plus a two-line `apply` that sends it, so what would reach the bar can be read
# and asserted exactly — the same trick `project` plays for the thinking.
#
# Two sections are worth reading. The GATE, because almost everything that
# happens to an agent must never reach the bar at all; and the SHELL, because a
# hover runs a command we generated, and a single stray quote in an agent's
# message would break it.
#
# The FLATTENING is next door, in `tests/markdown.nu`. It left with the code:
# `core/markdown.nu` is shared with the picker's preview now, so its assertions
# are not the bar's either.

use ../integrations/sketchybar
use ../core/dispatch.nu
use assert.nu *

# Agents in a known order: `state_since` is what a drawer sorts on, so it is
# spelled out rather than left to the prune-daemon.
def agents [...states: string]: nothing -> list<record> {
    $states | enumerate | each {|x| {
        id: $"a($x.index)"
        agent: "claude"
        state: $x.item
        name: $"agent-($x.index)"
        state_since: $"2026-09-12T10:0($x.index):00Z"
    }}
}

# An agent that arrived a given while ago. The flash is the one thing here that
# asks the clock a question, so it is the one thing that cannot be tested
# against a timestamp written into the file: `agents` above is all long past,
# which is why none of it flashes.
def stamped-ago [ago: duration]: nothing -> string {
    ((date now) - $ago) | date to-timezone UTC | format date "%Y-%m-%dT%H:%M:%S%.6fZ"
}
def arrival [id: string, state: string, ago: duration]: nothing -> record {
    {id: $id, agent: "claude", state: $state, name: $"agent-($id)", cwd: "/w",
     message: "Ready for you.", state_since: (stamped-ago $ago)}
}

# Every generated shell command, pulled back out of a message.
def scripts [msg: list<string>]: nothing -> list<string> {
    $msg | where {|x| ($x | str starts-with "script=") or ($x | str starts-with "click_script=") }
}

# The two are not the same kind of thing and stopped being interchangeable when
# the click landed: a `script` runs on hover AND on a forced `--update`, so it
# must guard on `$SENDER`; a `click_script` runs only when clicked, so it must
# not and does not.
def hover-scripts [msg: list<string>]: nothing -> list<string> {
    $msg | where {|x| $x | str starts-with "script=" }
}
def click-scripts [msg: list<string>]: nothing -> list<string> {
    $msg | where {|x| $x | str starts-with "click_script=" }
}

def row-of [rec: record, settings: record]: nothing -> record {
    sketchybar render-items [($rec | merge {state: "working"})] $settings | get "row|working|0"
}

export def main [] {
    let settings = sketchybar settings {}

    # ── settings ──────────────────────────────────────────────────────────────
    let a = [
        (check "there is a default for everything" ($settings | columns | sort)
               ["background" "binary" "colors" "flash_drawer" "flash_seconds" "font"
                "line_height" "position" "prefix" "preview_depth" "preview_lines"
                "preview_width" "row_width" "rows"])
        (check "the program is resolved to an ABSOLUTE path, not left to PATH"
               ($settings.binary | str starts-with "/") true)
        (check-err "…and a path that is not there is a loud error, not a silent no-op"
                   "no program at" {|| sketchybar settings {binary: "/nope/sketchybar"} })
        (check "the item prefix keeps v1 and v2 apart on one bar" $settings.prefix "an_")
        (check "a colour override replaces just that one"
               (sketchybar settings {colors: {working: "0xff000000"}} | get colors.working) "0xff000000")
        (check "…and leaves the rest alone"
               (sketchybar settings {colors: {working: "0xff000000"}} | get colors.awaiting)
               $settings.colors.awaiting)
        (check "the drawer has colours of its own, beyond the three states — and two for what a preview ROW IS"
               ($settings.colors | columns | sort)
               ["awaiting" "border" "code" "dim" "head" "needs-attention" "popup" "row" "text" "working"])
        (check "a different prefix is honoured"
               (sketchybar settings {prefix: "x_"} | get prefix) "x_")
        (check-err "a setting we do not have is a typo" "is not a setting"
                   {|| sketchybar settings {colour: "red"} })
        (check-err "a colour for something that is not a state is refused" "is not a colour we use"
                   {|| sketchybar settings {colors: {banana: "0xffffffff"}} })
        (check-err "a colour that is not 0xAARRGGBB is refused" "0xAARRGGBB"
                   {|| sketchybar settings {colors: {working: "red"}} })
        # The pool is built from these, so a bad one produces a drawer with no
        # slots in it and nothing to say why.
        (check-err "a row count of zero is refused" "must be a positive number"
                   {|| sketchybar settings {rows: 0} })
        (check-err "…and so is one that is not a number" "must be a positive number"
                   {|| sketchybar settings {preview_lines: "lots"} })
        # A SPAN is not a size: zero is a legal answer and means "never".
        (check "an arrival stays lit for a few seconds by default" $settings.flash_seconds 6)
        (check "…and takes its drawer with it" $settings.flash_drawer true)
        (check "a flash can be switched off without touching anything else"
               (sketchybar settings {flash_seconds: 0} | get flash_seconds) 0)
        (check-err "…but not with a word" "number of seconds"
                   {|| sketchybar settings {flash_seconds: "a while"} })
        (check-err "…and not backwards" "number of seconds"
                   {|| sketchybar settings {flash_seconds: -1} })
        (check-err "a switch takes true or false, not a number" "must be true or false"
                   {|| sketchybar settings {flash_drawer: 1} })
    ]

    # ── project: one key per slot ─────────────────────────────────────────────
    let m = sketchybar render-items (agents "working" "awaiting" "awaiting" "needs-attention") $settings
    let many = agents ...(1..12 | each {|| "working" })
    let capped = sketchybar settings {rows: 3}
    let b = [
        (check "agents are counted by state"
               ($m | select "count|working" "count|awaiting" "count|needs-attention")
               {"count|working": 1, "count|awaiting": 2, "count|needs-attention": 1})
        (check "…and each one gets a row of its own"
               ($m | columns | where {|k| $k | str starts-with "row|" } | sort)
               ["row|awaiting|0" "row|awaiting|1" "row|needs-attention|0" "row|working|0"])
        (check "an empty session-store is three zeros and no rows"
               (sketchybar render-items [] $settings)
               {"count|working": 0, "count|awaiting": 0, "count|needs-attention": 0})
        (check "idle is not a counter — a quiet agent gets no number and no row"
               (sketchybar render-items (agents "idle" "idle") $settings)
               {"count|working": 0, "count|awaiting": 0, "count|needs-attention": 0})
        (check "a state we have never heard of is counted as nothing"
               (sketchybar render-items [{id: "x", state: "napping"}] $settings)
               {"count|working": 0, "count|awaiting": 0, "count|needs-attention": 0})
        # Every row in a drawer shares a state, so the only ordering that says
        # anything is who has been in it longest.
        (check "the longest wait is at the top"
               [($m | get "row|awaiting|0" | get label) ($m | get "row|awaiting|1" | get label)]
               ["agent-1" "agent-2"])
        (check "a drawer is capped — the rest are counted, not drawn"
               (sketchybar render-items $many $capped | columns | where {|k| $k | str starts-with "row|" } | length) 3)
        (check "…and the count still tells the truth"
               (sketchybar render-items $many $capped | get "count|working") 12)
    ]

    # ── what a row says ───────────────────────────────────────────────────────
    let long_name = ("z" | fill --width 80 --character "z")
    let long = (1..60 | each {|i| $"para ($i)" } | str join "\n\n")
    let filter = sketchybar settings {preview_width: 40}
    let c = [
        (check "an agent's own name is its row"
               (row-of {id: "x", name: "build-the-thing", cwd: "/a/b"} $settings | get label) "build-the-thing")
        (check "…and without one, the directory it is working in"
               (row-of {id: "x", cwd: "/a/b/monomodules"} $settings | get label) "monomodules")
        (check "…and with neither, enough of its id to tell it apart"
               (row-of {id: "0123456789abcdef"} $settings | get label) "01234567")
        (check "a long name is cut to fit the drawer"
               (row-of {id: "x", name: $long_name} $settings | get label | split chars | length) $settings.row_width)
        (check "the first preview line says WHICH agent this is"
               (row-of {id: "x", cwd: "/a/b", zellij: {session: "home", tab_base: "root"}} $settings | get lines | first)
               {k: "where", t: "home/root · /a/b"})
        (check "…falling back to the agent when zellij is not in play"
               (row-of {id: "x", agent: "codex", cwd: "/a/b"} $settings | get lines | first | get t) "codex · /a/b")
        (check "a home directory is written the short way"
               (row-of {id: "x", cwd: ($nu.home-dir | path join "w")} $settings | get lines | first | get t
                | str contains "~/w") true)
        # A filter drawer, so the eliding is exercised rather than the 110
        # characters a real one has.
        (check "a directory too long for the row keeps its END, not its beginning"
               (row-of {id: "x", agent: "c", cwd: "/very/long/prefix/that/will/not/fit/anywhere/near/here/at/all/thing"} $filter
                | get lines | first | get t | str ends-with "/thing") true)
        (check "…and the cut lands on a separator rather than mid-word"
               (row-of {id: "x", agent: "c", cwd: "/very/long/prefix/that/will/not/fit/anywhere/near/here/at/all/thing"} $filter
                | get lines | first | get t | str contains "· …/") true)
        (check "an agent with nothing to say says so rather than nothing"
               (row-of {id: "x", cwd: "/a"} $settings | get lines | last | get t) "—")
        (check "the message follows the where-line, its heading marked and bound to what it introduces"
               (row-of {id: "x", cwd: "/a", message: "## Done\n\nAll **green**."} $settings | get lines)
               [{k: "where", t: "agent · /a"} {k: "head", t: "▊ Done"} {k: "text", t: "All green."}])
        # It is cut to what the footer HOLDS now, not to what it shows — the
        # rest is written to the bar switched off, and a wheel turns it on.
        (check "a preview never outgrows what the footer holds"
               ((row-of {id: "x", message: $long} $settings | get lines | length)
                <= ($settings.preview_depth + 1)) true)
        (check "…and it goes deeper than the screenful shown, which is what there is to scroll to"
               ((row-of {id: "x", message: $long} $settings | get lines | length)
                > $settings.preview_lines) true)
    ]

    # ── the gate: what must and must not reach the bar ────────────────────────
    let base = [{id: "a", state: "working", name: "one", cwd: "/x", state_since: "2026-01-01T00:00:00Z"}]
    let four = agents "awaiting" "awaiting" "awaiting" "awaiting"
    let renamed = $four | each {|r| if $r.id == "a2" { $r | upsert name "renamed" } else { $r } }
    let x = sketchybar render-items $four $settings
    let y = sketchybar render-items $renamed $settings
    let d = [
        (check "a re-asserted state is not a change — this is the one that fires constantly"
               (sketchybar render-items ($base | each {|r| $r | upsert state "working" }) $settings)
               (sketchybar render-items $base $settings))
        # v1's bar showed only numbers, so a message could never reach it. Now
        # it is a row's preview, and it must.
        (check "a NEW MESSAGE does reach the bar, because it is what a hover shows"
               ((sketchybar render-items ($base | upsert message "a long answer") $settings) != (sketchybar render-items $base $settings))
               true)
        (check "so does a rename"
               ((sketchybar render-items ($base | upsert name "two") $settings) != (sketchybar render-items $base $settings)) true)
        (check "a STATE change moves the counts as well as the rows"
               ((sketchybar render-items ($base | upsert state "awaiting") $settings) != (sketchybar render-items $base $settings))
               true)
        (check "…and so does an agent arriving"
               ((sketchybar render-items ($base ++ [{id: "b", state: "working"}]) $settings) != (sketchybar render-items $base $settings))
               true)
        # The whole reason for a map of slots: four agents, one moves, one key.
        (check "when one agent of four moves, ONE row key changes"
               ($y | columns | where {|k| ($x | get $k) != ($y | get $k) }) ["row|awaiting|2"])
    ]

    # ── the message that would be sent ────────────────────────────────────────
    let counter = sketchybar message {"count|working": 2} {} $settings
    let empty = sketchybar message {"count|working": 0} {} $settings
    let e = [
        (check "a changed count writes the item-name and its header in one message"
               ($counter | where {|q| $q == "--set" } | length) 2)
        (check "the item-name shows the number" ("label=2" in $counter) true)
        (check "…in its full colour when there is something to say"
               ($"icon.color=($settings.colors.working)" in $counter) true)
        (check "a counter at zero keeps its hue but loses its alpha"
               ($empty | any {|q| $q | str starts-with "icon.color=0x66" }) true)
        (check "…and its number goes muted rather than invisible"
               ($"label.color=($settings.colors.dim)" in $empty) true)
        (check "the header counts what the drawer holds" ("label=  2 active" in $counter) true)
        (check "…and says so when some are not drawn"
               ("label=  40 active · 10 shown" in (sketchybar message {"count|working": 40} {} $settings)) true)
        (check "an empty drawer says so instead" ("label=  All clear" in $empty) true)
        (check "needs-attention becomes a legal item name"
               ("an_attention" in (sketchybar message {"count|needs-attention": 1} {} $settings)) true)
        (check "a custom prefix reaches the items"
               ("x_working" in (sketchybar message {"count|working": 1} {} (sketchybar settings {prefix: "x_"})))
               true)
    ]

    # ── the shell the bar will run ────────────────────────────────────────────
    # A hover has nowhere to ask a question: whatever it shows was written into
    # the item by the paint that drew the row. These assert what that is.
    let open = scripts $counter | first
    let shut = scripts $empty | first
    let row = sketchybar message {"row|working|0": {id: "6923c0bc-1111", label: "one", lines: [{k: "where", t: "where"} {k: "text", t: "hello"}]}} {} $settings
    let hover = hover-scripts $row | first
    let f = [
        (check "every HOVER script guards on the sender"
               (hover-scripts ($counter ++ $row) | all {|q| $q | str contains '"$SENDER"' }) true)
        (check "…because a forced --update runs it too, and must not open a drawer"
               ($open | str contains "= mouse.entered ] || exit 0") true)
        (check "hovering a counter that has something to say opens ITS drawer"
               ($open | str contains "--set an_working popup.drawing=on") true)
        (check "…and shuts the other two, so sliding along the bar leaves no trail"
               (($open | str contains "--set an_awaiting popup.drawing=off")
                and ($open | str contains "--set an_attention popup.drawing=off")) true)
        (check "…and blanks its own footer, so it never reopens on the last row you read"
               ($open | str contains "--set an_working.pv.0 drawing=off") true)
        (check "an EMPTY counter opens nothing — that would be noise, not signal"
               ($shut | str contains "popup.drawing=on") false)
        (check "…but still shuts the others: moving off a counter means you are done"
               ($shut | str contains "--set an_working popup.drawing=off") true)
        (check "a row carries its whole preview, so a hover reads no session-store and spawns no nu"
               (($hover | str contains "'label=where'") and ($hover | str contains "'label=hello'")) true)
        (check "…and switches off the rows it did not fill"
               ($hover | str contains $"--set an_working.pv.($settings.preview_lines - 1) drawing=off") true)
        (check "an absolute program, because a daemon's PATH is not a shell's"
               ($hover | str contains $settings.binary) true)
        (check "the row itself is drawn and labelled" (("label=one" in $row) and ("drawing=on" in $row)) true)
    ]

    # THE ESCAPING, which is the one thing that can break a generated command.
    # Probed on the real daemon: inside single quotes $HOME and backticks stay
    # literal, so a lone apostrophe is the whole of the danger.
    #
    # THE AGENT'S TEXT GOES IN RAW. That is the assertion: escaping happens
    # where `items.nu` writes the quote, not in `project`, so what is fed here
    # is what an agent would actually say and what comes back is a command that
    # holds.
    let nasty = "it's `rm -rf /` $HOME \"x\" --set evil popup.drawing=on\r"
    let bad = hover-scripts (sketchybar message {"row|working|0": {label: $nasty, lines: [{k: "text", t: $nasty}]}} {} $settings) | first
    let g = [
        (check "a preview row is coloured by WHAT IT IS — a label has no ANSI, so the kind picks its one colour"
               (hover-scripts (sketchybar message {"row|working|0": {label: "x", lines: [
                    {k: "where", t: "w"} {k: "head", t: "h"} {k: "code", t: "c"} {k: "text", t: "p"}]}} {} $settings)
                | first | split row " " | where {|w| $w | str starts-with "label.color=" } | first 4)
               [$"label.color=0x99($settings.colors.working | str substring 4..)"
                $"label.color=($settings.colors.head)"
                $"label.color=($settings.colors.code)"
                $"label.color=($settings.colors.dim)"])
        (check "an apostrophe cannot reach the shell" ($bad | str contains "it's") false)
        (check "…because it is not an apostrophe any more" ($bad | str contains "it’s") true)
        (check "a quote count that is even is a command that cannot break out"
               (($bad | split chars | where {|q| $q == "'" } | length) mod 2) 0)
        (check "backticks and $HOME survive as text, because single quotes make them text"
               (($bad | str contains "`rm -rf /`") and ($bad | str contains "$HOME")) true)
        (check "a carriage return cannot end the command line early"
               ($bad | str contains "\r") false)
        (check "the PROJECTION keeps the agent's own words — escaping is not part of
           what should be shown"
               (row-of {name: "it's", message: "it's"} $settings | get label) "it's")
    ]

    # ── rows that go away ─────────────────────────────────────────────────────
    # `removed` is what dispatch hands back for a key that vanished — an agent
    # that ended, or one pushed past the cap.
    let gone = sketchybar message {} {"row|working|1": {label: "x", lines: []}} $settings
    let h = [
        (check "a row with no agent behind it is switched off"
               (("an_working.row.1" in $gone) and ("drawing=off" in $gone)) true)
        (check "…and its preview goes with it, rather than sitting on the item"
               ("script=" in $gone) true)
        (check "…and so does its click, which would otherwise point at a pane it lost"
               ("click_script=" in $gone) true)
        (check "a count is never removed — an emptied drawer goes to zero"
               (sketchybar message {} {"count|working": 3} $settings) [])
    ]

    # ── the click, which is the one thing that is NOT baked ───────────────────
    # A hover's answer is baked because the same paint wrote the text (D44). A
    # click's is not, because a jump is a decision about where an agent is NOW
    # and a pane can move with no state change at all — so the click runs the
    # module and the module re-reads the store (D76). What IS baked is the
    # invocation, and the only thing about the agent it carries is the id.
    let one_row = {"row|working|0": {id: "6923c0bc-1111", label: "one", lines: [{k: "text", t: "hi"}]}}
    let click = click-scripts (sketchybar message $one_row {} $settings) | first
    let j = [
        (check "a row's click carries its agent's id and nothing else about it"
               ($click | str contains "jump 6923c0bc-1111") true)
        (check "…and points at the COMMAND, not at the module — 22.6ms against 97.3ms"
               (($click | str contains "cli/jump.nu") and (not ($click | str contains "use \"agent-notify")))
               true)
        (check "…nor at any integration: the registry decides which one has it"
               ($click | str contains "zellij") false)
        (check "an ABSOLUTE nu, because a click runs with launchd's PATH"
               ($click | str contains $"exec ($nu.current-exe) ") true)
        (check "the drawers shut first, so no popup is left over another application"
               ($click | str starts-with $"click_script=($settings.binary) --set an_working popup.drawing=off")
               true)
        (check "a click_script does NOT guard on the sender — only a click runs it"
               ($click | str contains '"$SENDER"') false)
        # Cannot happen from a live paint, but a value written by an older paint
        # can reach `row-args` through the diff.
        (check "a row with no id gets no click at all, rather than one going nowhere"
               (click-scripts (sketchybar message {"row|working|0": {label: "one", lines: []}} {} $settings))
               ["click_script="])
    ]

    # ── the flash: an arrival that lights itself, and puts itself out ─────────
    # The ONE thing in this display that is not a pure function of its records,
    # because "just arrived" is a question about the clock. So these records are
    # stamped as the suite runs, and everything else in this file is long past
    # on purpose — otherwise half the assertions above would be flashing.
    let just_in = arrival "a" "awaiting" 1sec
    let fresh = sketchybar render-items [$just_in] $settings
    let stale = sketchybar render-items [(arrival "a" "awaiting" 1hr)] $settings
    let busy = sketchybar render-items [(arrival "a" "working" 1sec)] $settings
    let two = [(arrival "a" "awaiting" 4sec) (arrival "b" "awaiting" 1sec)]
    let queue = sketchybar render-items $two $settings
    let muted = sketchybar render-items [$just_in] (sketchybar settings {flash_seconds: 0})
    let undated = sketchybar render-items [{id: "a", state: "awaiting", name: "x"}] $settings
    let past_cap = sketchybar render-items $two (sketchybar settings {rows: 1})
    let n = [
        (check "an agent that has just arrived is announced, and the drawer knows where to look"
               ($fresh | get flash | reject lines) {state: "awaiting", index: 0, until: ($fresh | get flash.until)})
        (check "…carrying its own words, so the drawer opens saying what happened"
               ($fresh | get flash.lines | last | get t) "Ready for you.")
        (check "the moment it ends is WHEN IT ARRIVED plus the window, so a later repaint cannot push it away"
               ($fresh | get flash.until)
               ((($just_in.state_since | into datetime) + 6sec) | format date "%s" | into int))
        (check "one that has been waiting an hour is not news" ($stale | get -o flash) null)
        (check "and an agent getting on with its work is never news, however fresh"
               ($busy | get -o flash) null)
        # A newer notification supersedes an older one. Anything else and the
        # bar would be announcing whatever happened to sort first.
        (check "the most recent arrival wins" ($queue | get flash.index) 1)
        (check "…and it is the one whose row is lit"
               ($queue | columns | where {|k| $k | str starts-with "row|" }
                | each {|k| $queue | get $k | get flash })
               [false true])
        (check "a chip lights even for an agent past the cap, because the NUMBER moving is the news"
               ($past_cap | get flash | reject lines) {state: "awaiting", index: null, until: ($past_cap | get flash.until)})
        (check "zero seconds is how you say never" ($muted | get -o flash) null)
        (check "…and it leaves no lit row behind either"
               ($muted | get "row|awaiting|0" | get flash) false)
        (check "a record that never said when it changed cannot be new"
               ($undated | get -o flash) null)
    ]

    # WHAT A RAISE SENDS. One message: the drawer, then the timer, then the chip
    # behind the fade — and the fade LAST, because `--animate` colours every
    # property set after it in the same message and none before it (probed).
    let raise = sketchybar message {flash: ($fresh | get flash)} {} $settings
    let quiet = sketchybar message {flash: ($fresh | get flash)} {} (sketchybar settings {flash_drawer: false})
    let timer_script = $raise | where {|q| $q | str starts-with "script=[" } | first
    let fade = $raise | skip ($raise | enumerate | where {|e| $e.item == "--animate" } | get 0.index)
    let o = [
        (check "the chip lights in its own state's hue"
               ($"background.color=0x33($settings.colors.awaiting | str substring 4..)" in $raise) true)
        (check "…with an edge, which is what actually catches the eye"
               ("background.border_width=1" in $raise) true)
        (check "…and it fades in rather than appearing"
               ($fade | first 3) ["--animate" "sin" "18"])
        (check "…with nothing after the fade but the chip, because --animate colours all of it"
               ($fade | length) 8)
        (check "the drawer opens itself" ("popup.drawing=on" in $raise) true)
        (check "…and shuts the other two, exactly as a hover would"
               ($raise | where {|q| $q == "popup.drawing=off" } | length) 2)
        (check "…already filled with what the agent said, so there is nothing to hover for"
               ("label=Ready for you." in $raise) true)
        (check "a drawer that was told not to open does not, and its chip still lights"
               [("popup.drawing=on" in $quiet) ("background.border_width=1" in $quiet)] [false true])
        (check "the one timer on the bar is armed" ("update_freq=1" in $raise) true)
        (check "…and nothing else in the message is"
               ($raise | where {|q| $q | str starts-with "update_freq" } | length) 1)
    ]

    # THE TIMER'S SCRIPT is the whole of "temporarily". It is baked at the raise
    # because that is the only moment that knows what got lit; it holds a
    # deadline rather than a countdown, so an unrelated repaint cannot extend
    # it; and re-arming REWRITES it, which is why cancellation needs no
    # generation counter anywhere.
    let p = [
        (check "the timer knows the moment, not a countdown"
               ($timer_script | str contains $"-ge ($fresh | get flash.until)") true)
        (check "…asks the clock itself, because a tick it missed must not extend it"
               ($timer_script | str contains '"$(date +%s)"') true)
        (check "…and does nothing at all until then"
               ($timer_script | str contains "|| exit 0") true)
        (check "a tick that is not the routine one is not a deadline"
               ($timer_script | str contains '[ "$SENDER" = routine ]') true)
        (check "when it fires it puts the chip back, shuts the drawer it opened, and stands down"
               (($timer_script | str contains "--set an_awaiting background.color=0x00000000")
                and ($timer_script | str contains "--set an_awaiting popup.drawing=off")) true)
        (check "…and only ITS drawer: it must not shut one you opened yourself in the meantime"
               ($timer_script | str contains "an_working popup.drawing=off") false)
        (check "…and unlights the row it lit, which is why the row index is in the projection"
               ($timer_script | str contains "an_awaiting.row.0 background.color=") true)
        (check "standing down means the timer stops AND forgets, so a hover afterwards runs nothing"
               ($timer_script | str contains "--set an_flash update_freq=0 script=") true)
        # The pointer arriving is the announcement being read. It ends the
        # flash — but it must not shut the drawer, because from that moment the
        # pointer owns it and that is the one thing that would be unforgivable.
        (check "the pointer can end it early" ($timer_script | str contains '"$SENDER" = an_flash_seen') true)
        (check "…and when it does, the drawer is left exactly where it is"
               ($timer_script | split row "; " | first | str contains "popup.drawing") false)
    ]

    # WHO SAYS SEEN. Every hover of ours, which costs one token on a message
    # that was being sent anyway.
    let counter_hover = hover-scripts (sketchybar message {"count|working": 2} {} $settings) | first
    let empty_hover = hover-scripts (sketchybar message {"count|working": 0} {} $settings) | first
    let row_hover = hover-scripts (sketchybar message {"row|working|0": {id: "x", label: "one", lines: [{k: "text", t: "hi"}]}} {} $settings) | first
    let q = [
        (check "hovering a counter tells the flash it has been seen"
               ($counter_hover | str contains "--trigger an_flash_seen") true)
        (check "…an empty one too, because you are at the bar either way"
               ($empty_hover | str contains "--trigger an_flash_seen") true)
        (check "…and a row, because a pointer can reach one without crossing the counter above it"
               ($row_hover | str contains "--trigger an_flash_seen") true)
    ]

    # ── the footer, and scrolling it ─────────────────────────────────────────
    # The footer HOLDS `preview_depth` rows and SHOWS `preview_lines - 1` of
    # them. Everything below the fold is written to the bar by the same paint
    # and left switched off, which is what makes a scroll `drawing=on` and
    # nothing else — no text moves, so nothing a wheel does can need quoting.
    let deep = row-of {id: "x", message: $long} $settings
    let filled = sketchybar message {"row|awaiting|0": ($deep | merge {id: "x"})} {} $settings
    let footer = hover-scripts $filled | first
    let short = sketchybar message {"row|awaiting|0": {id: "x", label: "one", lines: [{k: "where", t: "w"} {k: "text", t: "hi"}]}} {} $settings
    let t = [
        (check "the footer is written as deep as it HOLDS"
               ($footer | str contains $"an_awaiting.pv.($settings.preview_depth) ") true)
        (check "…but only a screenful of it is switched on"
               ($footer | split row " --set " | where {|q| $q | str starts-with "an_awaiting.pv." }
                | where {|q| $q | str contains "drawing=on" } | length)
               $settings.preview_lines)
        # The bug this was written for: the rows below the fold were switched
        # off and never given their words, so a wheel revealed blank lines.
        (check "…and every line the agent wrote is WRITTEN, drawn or not"
               ($footer | str contains "an_awaiting.pv.20 'label=") true)
        (check "…while a slot with no line behind it is only switched off, never labelled — the
           window is clamped to what is held, so nothing can scroll onto it"
               ($footer | str contains $"an_awaiting.pv.($settings.preview_depth) drawing=off") true)
        (check "…starting at the top, under the WHERE line, however often it is repainted"
               ($footer | str contains $"--set an_scroll icon=pv:an_awaiting:") true)
        (check "the position says which drawer, how much it holds, and where the window is"
               ($footer | str contains "icon=pv:an_awaiting:39:0") true)
        (check "a footer with more under it says how much"
               ($footer | str contains "--set an_awaiting.more label=28 drawing=on") true)
        (check "…and one that fits says nothing at all"
               ($short | any {|q| $q | str contains "an_awaiting.more drawing=off" })
               ($short | any {|q| $q | str contains "more" }))
    ]

    # WHO CATCHES A WHEEL. A mouse event reaches only the item under the
    # pointer, and that is a different row every time — so everything in a
    # drawer forwards one trigger and the thinking lives once.
    let inst_s = sketchybar install-message $settings
    let handler = $inst_s | where {|q| $q | str starts-with "script=[ \"$SENDER\" = an_scrolled" } | first
    let u = [
        (check "a row forwards a wheel, because you scroll the preview of the row you are on"
               ($footer | str starts-with "script=[ \"$SENDER\" = mouse.scrolled ] && exec") true)
        (check "…and still opens its preview on a hover, after"
               ($footer | str contains "= mouse.entered ] || exit 0") true)
        (check "a footer line forwards one too" ("mouse.scrolled" in $inst_s) true)
        (check "…and the delta rides along with it"
               ($footer | str contains "--trigger an_scrolled SCROLL_DELTA=$SCROLL_DELTA") true)
        (check "one item hears them all, and it is not a row"
               (($inst_s | any {|q| $q == "an_scroll" }) and ($handler | is-not-empty)) true)
    ]

    # THE SCROLL SCRIPT IS STATIC — written once at install and never by a
    # paint, because the paint already put the text on the bar and this only
    # decides which rows are drawn. Its arithmetic was run against a fake bar
    # (§11); what the suite owns is that it asks the right questions.
    let v = [
        (check "it reads the position back out of its own item"
               ($handler | str contains "--query an_scroll") true)
        (check "…finding it by an anchor, not by where the JSON happens to put it"
               ($handler | str contains "${q#*'\"pv:'}") true)
        (check "a drawer holding no more than it shows is not scrollable, and says so first"
               ($handler | str contains '[ "$n" -gt "$w" ] || exit 0') true)
        (check "…and neither is the zero delta a gesture opens with"
               ($handler | str contains '[ "$d" -eq 0 ] && exit 0') true)
        (check "the window is clamped at both ends"
               (($handler | str contains '[ "$k" -lt 0 ] && k=0')
                and ($handler | str contains '[ "$k" -gt "$x" ] && k=$x')) true)
        (check "…and a wheel that moves nothing sends nothing"
               ($handler | str contains '[ "$k" -eq "$p" ] && exit 0') true)
        (check "a shove moves further than a nudge — the delta carries momentum"
               ($handler | str contains "m=${d#-}") true)
        (check "nothing it sends can carry a word the agent wrote"
               ($handler | str contains "label=") ($handler | str contains "label=$b"))
        (check "it is written once and no paint rewrites it"
               (sketchybar message (sketchybar render-items (agents "awaiting") $settings) {} $settings
                | any {|q| $q | str contains "an_scrolled ] || exit 0" }) false)
    ]

    # WHAT A ROW LOOKS LIKE WHEN IT IS THE ONE. The pill is a diffed fact rather
    # than something the flash reaches in and sets, because a flashing agent's
    # row MOVES when an older one leaves the state — and only the diff knows
    # both slots.
    let lit_row = sketchybar message {"row|awaiting|0": {id: "x", label: "one", lines: [], flash: true}} {} $settings
    let dim_row = sketchybar message {"row|awaiting|0": {id: "x", label: "one", lines: [], flash: false}} {} $settings
    let void = sketchybar message {} {flash: {state: "awaiting", index: 0, until: 1789387358}} $settings
    let r = [
        (check "the lit row wears its state's hue" ($"background.color=0x33($settings.colors.awaiting | str substring 4..)" in $lit_row) true)
        (check "…and every other row the drawer's own" ($"background.color=($settings.colors.row)" in $dim_row) true)
        (check "…which is what unlights the one that stopped being it, with no flash involved"
               ("background.border_width=0" in $dim_row) true)
        # `removed` is the third way a flash can end: the agent went back to
        # work before its window was out, so the announcement is void.
        (check "an agent that leaves the state takes its announcement with it"
               (("--set an_awaiting background.color=0x00000000" in ($void | str join " "))
                and ("popup.drawing=off" in $void)) true)
        (check "…and the timer with it, so nothing is left ticking for a flash that is gone"
               ("update_freq=0" in $void) true)
    ]

    # ── the item pool, created once ───────────────────────────────────────────
    let inst = sketchybar install-message $settings
    let small = sketchybar install-message (sketchybar settings {rows: 2, preview_lines: 3, preview_depth: 5})
    let painted = sketchybar message (sketchybar render-items (agents "working") $settings) {} $settings
    let i = [
        # Three counters, and behind each a header, its rows, a footer as deep
        # as it HOLDS and the line that says how much is under it. Then the
        # exit, the flash, the scroll, the bracket — and the two events, which
        # `--add` also builds.
        (check "the whole bar in one message"
               ($inst | where {|q| $q == "--add" } | length)
               (3 + (3 * (1 + $settings.rows + ($settings.preview_depth + 1) + 1)) + 6))
        (check "…and the pool follows the settings"
               ($small | where {|q| $q == "--add" } | length) (3 + (3 * (1 + 2 + 6 + 1)) + 6))
        (check "the counters are bracketed into one pill" ("bracket" in $inst) true)
        (check "a re-run wipes each drawer first, so changing `rows` leaves no orphans"
               ($inst | any {|q| $q == '/an_working\..*/' }) true)
        # v1 hung a hidden 30s item off this pool to prune dead agents, which
        # made a core guarantee depend on one optional display being installed.
        # The one timer here is the flash's own and expires nothing but a
        # highlight — liveness is still the prune-daemon's, and still not a
        # display's job.
        (check "the only timer on the bar belongs to the flash, and arrives disarmed"
               ($inst | where {|q| $q | str starts-with "update_freq" }) ["update_freq=0"])
        (check "…with nothing in it, so a hover between flashes runs no shell at all"
               (($inst | any {|q| $q == "an_flash" }) and ("script=" in $inst)) true)
        (check "…listening for the pointer on an event of its own, declared before it subscribes"
               (($inst | take until {|q| $q == "an_flash" } | any {|q| $q == "an_flash_seen" })) true)
        (check "a chip carries its pill from the start, invisible, so a flash has something to fade in"
               (($inst | any {|q| $q == "background.drawing=on" })
                and ($inst | any {|q| $q == "background.color=0x00000000" })) true)
        (check "a counter listens for the pointer arriving" ("mouse.entered" in $inst) true)
        (check "leaving the bar shuts every drawer, from an item of its own"
               (($inst | any {|q| $q == "an_exit" }) and ("mouse.exited.global" in $inst)) true)
        (check "…and that one never needs rewriting, so a paint never touches it"
               ($painted | any {|q| $q == "an_exit" }) false)
        (check "clicking a counter dismisses the drawer"
               ($inst | any {|q| ($q | str starts-with "click_script=") and ($q | str contains "popup.drawing=off") })
               true)
        (check "the glyphs survived being written as escapes"
               ($inst | any {|q| ($q | str starts-with "icon=") and (($q | str length) > 5) }) true)
        (check "a fresh counter starts at zero" ("label=0" in $inst) true)
    ]

    # ── it is a display like any other ────────────────────────────────────────
    let k = [
        (check "dispatch ships it"
               ("sketchybar" in (dispatch integration-registry-names)) true)
        (check "…with the parts every display has"
               (dispatch integration-registry | get sketchybar | columns | sort)
               ["info" "push-items" "render-items" "settings"])
        (check "…and no `discover-own-location`: a bar can see nothing about its own process"
               (dispatch integration-registry | get sketchybar | get -o discover-own-location) null)
        (check "zellij does have one, because it can"
               (dispatch integration-registry | get zellij
                | get -o discover-own-location | is-not-empty) true)
    ]

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f ++ $g ++ $h ++ $j ++ $i ++ $k)
    let flashed = ($n ++ $o ++ $p ++ $q ++ $r)
    let scrolled = ($t ++ $u ++ $v)
    summarise ($all ++ $flashed ++ $scrolled) --title "sketchybar display"
}
