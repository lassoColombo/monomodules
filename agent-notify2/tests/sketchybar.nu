# Step 5 — the SketchyBar counters.
#
# Not one subprocess runs in this suite, and no bar has to be installed. That is
# on purpose: the surface splits the SIDE EFFECT into a pure `message` builder
# plus a two-line `apply` that sends it, so what would reach the bar can be read
# and asserted exactly — the same trick `project` plays for the thinking.
#
# The section worth reading is the gate: a counter shows only a number, so almost
# everything that happens to an agent projects identically and must never reach
# the bar at all.

use ../surfaces/sketchybar.nu
use ../core/dispatch.nu
use assert.nu *

def agents [...states: string]: nothing -> list<record> {
    $states | enumerate | each {|x| {id: $"a($x.index)", client: "claude", state: $x.item} }
}

export def main [] {
    let s = sketchybar settings {} null

    # ── settings ─────────────────────────────────────────────────────────────
    let a = [
        (check "there is a default for everything" ($s | columns | sort)
               ["background" "colors" "font" "position" "prefix"])
        (check "the item prefix keeps v1 and v2 apart on one bar" $s.prefix "an_")
        (check "a colour override replaces just that one"
               (sketchybar settings {colors: {working: "0xff000000"}} null | get colors.working) "0xff000000")
        (check "…and leaves the rest alone"
               (sketchybar settings {colors: {working: "0xff000000"}} null | get colors.awaiting)
               $s.colors.awaiting)
        (check "a different prefix is honoured"
               (sketchybar settings {prefix: "x_"} null | get prefix) "x_")
        (check-err "a setting we do not have is a typo" "is not a setting"
                   {|| sketchybar settings {colour: "red"} null })
        (check-err "a colour for something that is not a state is refused" "is not a colour we use"
                   {|| sketchybar settings {colors: {banana: "0xffffffff"}} null })
        (check-err "a colour that is not 0xAARRGGBB is refused" "0xAARRGGBB"
                   {|| sketchybar settings {colors: {working: "red"}} null })
    ]

    # ── project: three numbers, and nothing else ─────────────────────────────
    let m = sketchybar project (agents "working" "awaiting" "awaiting" "needs-attention") $s
    let b = [
        (check "agents are counted by state" $m {working: 1, awaiting: 2, needs-attention: 1})
        (check "an empty store is three zeros"
               (sketchybar project [] $s) {working: 0, awaiting: 0, needs-attention: 0})
        (check "idle is not a counter — a quiet agent gets no number"
               (sketchybar project (agents "idle" "idle") $s)
               {working: 0, awaiting: 0, needs-attention: 0})
        (check "a state we have never heard of is counted as nothing"
               (sketchybar project [{id: "x", state: "napping"}] $s)
               {working: 0, awaiting: 0, needs-attention: 0})
    ]

    # ── the gate: what must NOT reach the bar ────────────────────────────────
    # If any of these fail, the bar is repainted for changes it cannot show.
    let base = [{id: "a", state: "working", name: "one", cwd: "/x"}]
    let c = [
        (check "a new message projects identically, so the bar is not touched"
               (sketchybar project ($base | upsert message "a long answer") $s)
               (sketchybar project $base $s))
        (check "…so does a rename"
               (sketchybar project ($base | upsert name "two") $s) (sketchybar project $base $s))
        (check "…and a directory change"
               (sketchybar project ($base | upsert cwd "/y") $s) (sketchybar project $base $s))
        (check "a STATE change does reach it"
               ((sketchybar project ($base | upsert state "awaiting") $s) != (sketchybar project $base $s))
               true)
        (check "…and so does an agent arriving"
               ((sketchybar project ($base ++ [{id: "b", state: "working"}]) $s) != (sketchybar project $base $s))
               true)
    ]

    # ── the message that would be sent ───────────────────────────────────────
    let msg = sketchybar message {working: 1, awaiting: 0, needs-attention: 0} $s
    let d = [
        (check "one message covers all three counters — batching is free"
               ($msg | where {|x| $x == "--set" } | length) 3)
        (check "needs-attention becomes a legal item name"
               ("an_attention" in $msg) true)
        (check "a live counter wears its full colour"
               ($"icon.color=($s.colors.working)" in $msg) true)
        (check "…and shows the number" ("label=1" in $msg) true)
        (check "a counter at zero keeps its hue but loses its alpha"
               ($msg | any {|x| $x | str starts-with "icon.color=0x66" }) true)
        (check "…and its number goes muted rather than invisible"
               ($"label.color=($s.colors.dim)" in $msg) true)
        (check "a custom prefix reaches the items"
               ("x_working" in (sketchybar message {working: 1} (sketchybar settings {prefix: "x_"} null)))
               true)
    ]

    # ── the item pool, created once ──────────────────────────────────────────
    let inst = sketchybar install-message $s
    let e = [
        (check "three counters, a bracket and a hidden tick are added"
               ($inst | where {|x| $x == "--add" } | length) 5)
        (check "the counters are bracketed into one pill" ("bracket" in $inst) true)
        (check "the tick runs every 30 seconds" ("update_freq=30" in $inst) true)
        (check "…and is the janitor: it prunes before it repaints"
               ($inst | any {|x| $x | str contains "surfaces refresh" }) true)
        (check "…without being visible" ("drawing=off" in $inst) true)
        (check "the glyphs survived being written as escapes"
               ($inst | any {|x| ($x | str starts-with "icon=") and (($x | str length) > 5) }) true)
        (check "a fresh counter starts at zero" ("label=0" in $inst) true)
    ]

    # ── it is a surface like any other ───────────────────────────────────────
    let f = [
        (check "dispatch ships it" ("sketchybar" in (dispatch known)) true)
        (check "…with the four things every surface has"
               (dispatch shipped | get sketchybar | columns | sort) ["apply" "info" "project" "settings"])
    ]

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f)
    summarise $all --title "sketchybar surface"
}
