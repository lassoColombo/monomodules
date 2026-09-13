# Case group 1 — THE FLOOR: what one process costs before our code does
# anything, and what pointing `use` at different depths of the tree adds on top.
#
# This is the group the whole architecture rests on. If a nu spawn is ~13ms and
# a bash spawn is ~2ms, then principle 1 ("all logic in nushell") has a price,
# and the only question left is how much of it we can hand back by narrowing
# what gets parsed — which is what the `use` ladder below measures.
#
# `-I <repo>` rather than NU_LIB_DIRS throughout: same effect on the parse, and
# it survives being handed down two process hops (see harness.nu's `cpu`).

use harness.nu *

const REPO = path self ../..

# The `use` ladder, cheapest first: a leaf, the HOT CONE a hook actually pays,
# and the whole module a human pays at a prompt.
#
# It used to climb the old module's tree, up to `use ai` — the whole provider
# tree that every v1 hook parsed, which is the measurement that started this
# rewrite. That module is gone, so the ladder now measures the thing it argued
# for: the gap between the top two rows is what the hot/cold split is worth, and
# §4.4 is the rule that keeps it there.
const LADDER = [
    [label                           code];
    ["(nothing)"                     ""]
    ["leaf core/paths.nu"            "use agent-notify/core/paths.nu"]
    ["leaf core/session-store.nu"            "use agent-notify/core/session-store.nu"]
    ["the HOT cone (what a hook pays)" "use agent-notify/agents/claude.nu"]
    ["the whole module (what a human pays)" "use agent-notify"]
]

def nu-args [code: string] { [$NU "-n" "--no-std-lib" "-I" $REPO "-c" $code] }

export def main [] {
    print "── spawn floor (ms) ─────────────────────────────────────────────────"
    print ([
        (wall "/usr/bin/true          (spawn floor)" ["/usr/bin/true"])
        (wall "/bin/bash -c ''        (bash floor)" ["/bin/bash" "-c" ""])
        (wall "/bin/sh -c ''" ["/bin/sh" "-c" ""])
        (wall "nu -n --no-std-lib -c ''" [$NU "-n" "--no-std-lib" "-c" ""])
        (wall "nu -n -c ''            (std lib on)" [$NU "-n" "-c" ""])
        (wall "nu -c ''               (+ user config)" [$NU "-c" ""])
    ] | fmt | table)

    print ""
    print "── parse cost: nu's own evaluate_commands span (ms) ─────────────────"
    print ($LADDER | each {|c| span $c.label $c.code --flags ["-n" "--no-std-lib" "-I" $REPO] } | fmt | table)

    print ""
    print "── same ladder, whole process wall time (ms) ────────────────────────"
    print ($LADDER | each {|c| wall $c.label (nu-args $c.code) } | fmt | table)

    print ""
    print "── amortised CPU per spawn (ms) ─────────────────────────────────────"
    print ([
        (cpu "/usr/bin/true" ["/usr/bin/true"])
        (cpu "/bin/bash -c ''" ["/bin/bash" "-c" ""])
        (cpu "nu -c '' (no std lib)" (nu-args ""))
        (cpu "nu -c 'use core/session-store.nu'" (nu-args "use agent-notify/core/session-store.nu"))
        (cpu "nu -c 'use agents/claude.nu'  (the hook)" (nu-args "use agent-notify/agents/claude.nu"))
        (cpu "nu -c 'use agent-notify'      (the CLI)" (nu-args "use agent-notify"))
    ] | fmt-cpu | table)
}
