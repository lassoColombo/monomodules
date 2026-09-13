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

# Every generated shell command, pulled back out of a message.
def scripts [msg: list<string>]: nothing -> list<string> {
    $msg | where {|x| ($x | str starts-with "script=") or ($x | str starts-with "click_script=") }
}

def row-of [rec: record, settings: record]: nothing -> record {
    sketchybar render-items [($rec | merge {state: "working"})] $settings | get "row|working|0"
}

export def main [] {
    let settings = sketchybar settings {}

    # ── settings ──────────────────────────────────────────────────────────────
    let a = [
        (check "there is a default for everything" ($settings | columns | sort)
               ["background" "binary" "colors" "font" "line_height" "position" "prefix"
                "preview_lines" "preview_width" "row_width" "rows"])
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
        (check "a preview never outgrows its drawer"
               (row-of {id: "x", message: (1..60 | each {|i| $"para ($i)" } | str join "\n\n")} $settings
                | get lines | length) $settings.preview_lines)
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
    let row = sketchybar message {"row|working|0": {label: "one", lines: [{k: "where", t: "where"} {k: "text", t: "hello"}]}} {} $settings
    let hover = scripts $row | first
    let f = [
        (check "every generated script guards on the sender"
               (scripts ($counter ++ $row) | all {|q| $q | str contains '"$SENDER"' }) true)
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
    let bad = scripts (sketchybar message {"row|working|0": {label: $nasty, lines: [{k: "text", t: $nasty}]}} {} $settings) | first
    let g = [
        (check "a preview row is coloured by WHAT IT IS — a label has no ANSI, so the kind picks its one colour"
               (scripts (sketchybar message {"row|working|0": {label: "x", lines: [
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
        (check "a count is never removed — an emptied drawer goes to zero"
               (sketchybar message {} {"count|working": 3} $settings) [])
    ]

    # ── the item pool, created once ───────────────────────────────────────────
    let inst = sketchybar install-message $settings
    let small = sketchybar install-message (sketchybar settings {rows: 2, preview_lines: 3})
    let painted = sketchybar message (sketchybar render-items (agents "working") $settings) {} $settings
    let i = [
        (check "three counters, three headers, their rows and previews, an exit and a bracket"
               ($inst | where {|q| $q == "--add" } | length)
               (3 + (3 * (1 + $settings.rows + $settings.preview_lines)) + 1 + 1))
        (check "…and the pool follows the settings"
               ($small | where {|q| $q == "--add" } | length) (3 + (3 * (1 + 2 + 3)) + 1 + 1))
        (check "the counters are bracketed into one pill" ("bracket" in $inst) true)
        (check "a re-run wipes each drawer first, so changing `rows` leaves no orphans"
               ($inst | any {|q| $q == '/an_working\..*/' }) true)
        (check "the bar owns NO timer — the prune-daemon is not a display's job"
               ($inst | any {|q| $q | str contains "update_freq" }) false)
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

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f ++ $g ++ $h ++ $i ++ $k)
    summarise $all --title "sketchybar display"
}
