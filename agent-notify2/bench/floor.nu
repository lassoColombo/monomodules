# Case group 1 — THE FLOOR: what one process costs before our code does anything,
# and what pointing `use` at different depths of the tree adds on top.
#
# This is the group the whole architecture rests on. If a nu spawn is ~13ms and a
# bash spawn is ~2ms, then principle 1 ("all logic in nushell") has a price, and
# the only question left is how much of it we can hand back by narrowing what
# gets parsed — which is what the `use` ladder below measures.
#
# `-I <repo>` rather than NU_LIB_DIRS throughout: same effect on the parse, and
# it survives being handed down two process hops (see harness.nu's `cpu`).

use harness.nu *

const REPO = path self ../..
const SKIM = ($nu.home-dir | path join ".cargo" "bin" "nu_plugin_skim")

# The `use` ladder, cheapest first — a leaf file, a selective import from the big
# module, the module, the whole `ai` tree (what every v1 hook pays today).
const LADDER = [
    [label                          code];
    ["(nothing)"                    ""]
    ["leaf lib/state.nu"            "use ai/agent-notify/lib/state.nu"]
    ["leaf lib/store.nu"            "use ai/agent-notify/lib/store.nu"]
    ["leaf lib/view.nu"             "use ai/agent-notify/lib/view.nu"]
    ["agent-notify list (selective)" "use ai/agent-notify list"]
    ["agent-notify (whole)"         "use ai/agent-notify"]
    ["ai (v1 hook)"                 "use ai"]
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
        (wall "nu -n --no-std-lib --plugins skim -c ''" [$NU "-n" "--no-std-lib" "--plugins" $SKIM "-c" ""])
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
        (cpu "nu -c 'use leaf store.nu'" (nu-args "use ai/agent-notify/lib/store.nu"))
        (cpu "nu -c 'use ai'" (nu-args "use ai"))
        (cpu "nu -n -c 'use ai'   (v1 hook, std lib on)" [$NU "-n" "-I" $REPO "-c" "use ai"])
    ] | fmt-cpu | table)
}
