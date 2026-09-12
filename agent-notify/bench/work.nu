# Case group 3 — THE OUTSIDE WORLD: what the store and the three external tools
# cost once a process is up. One of these — zellij's per-event query, which v1
# runs on EVERY apply — is a candidate for dominating everything the parse budget
# argues about, which is the point of measuring it.
#
# (Store I/O lives in store_bench.nu, which needs its own XDG_DATA_HOME.)
#
# SAFETY — nothing here may disturb the live surfaces:
#   - zellij reads (`list-panes`, `list-sessions`) are read-only, run against the
#     real session.
#   - the zellij WRITE targets pane id 99999, which does not exist: the
#     client→server round trip is paid in full but no pane is renamed. An
#     approximation of a real rename, and flagged as one below.
#   - sketchybar gets a hidden throwaway item and a subscriber-less event, so no
#     drawer repaints and no `render.sh` storm pollutes the numbers. Removed after.

use harness.nu *

const SB = "/opt/homebrew/bin/sketchybar"
const ZJ = "/opt/homebrew/bin/zellij"

export def zellij [] {
    let sess = $env.ZELLIJ_SESSION_NAME? | default "home"
    print "── zellij (ms) ──────────────────────────────────────────────────────"
    print ([
        (wall "list-panes -t -j       (v1: EVERY apply)" [$ZJ "--session" $sess "action" "list-panes" "-t" "-j"] --rounds 25)
        (wall "rename-pane, bogus id  (v1: every apply)" [$ZJ "--session" $sess "action" "rename-pane" "--pane-id" "99999" "bench"] --rounds 25)
        (wall "list-sessions -n       (v1: the GC scan)" [$ZJ "list-sessions" "-n"] --rounds 25)
        (wall "action on dead session (failure path)" [$ZJ "--session" "no-such-session-xyz" "action" "list-panes" "-t" "-j"] --rounds 15)
    ] | fmt | table --width 100)
}

export def sketchybar [] {
    print "── sketchybar (ms) ──────────────────────────────────────────────────"
    ^$SB --add event bench_noop | complete | ignore
    ^$SB --add item bench_item left --set bench_item drawing=off | complete | ignore
    let props = {|n| ["--set" "bench_item"] ++ (1..$n | each {|i| $"label=v($i)" }) }
    let out = [
        (wall "--trigger, no subscriber  (v1: the poke)" [$SB "--trigger" "bench_noop"] --rounds 25)
        (wall "--set 1 property" ([$SB] ++ (do $props 1)) --rounds 25)
        (wall "--set 50 properties" ([$SB] ++ (do $props 50)) --rounds 25)
        (wall "--set 200 properties      (v1: a full paint)" ([$SB] ++ (do $props 200)) --rounds 25)
        (wall "--query bar               (a read)" [$SB "--query" "bar"] --rounds 15)
    ]
    ^$SB --remove bench_item | complete | ignore
    print ($out | fmt | table --width 100)
}

export def pandoc [] {
    print "── pandoc (ms) — v1 runs this on the hook path, per preview ──────────"
    let short = "Claude needs your permission to run a command."
    let md = 1..12 | each {|l| $"- a **bullet** with `code` and some prose, line ($l)." } | str join "\n"
    print ([
        (wall "pandoc gfm→plain (46 chars)" ["/opt/homebrew/bin/pandoc" "-f" "gfm" "-t" "plain" "--wrap=none" "--columns=62"] --rounds 15 --stdin $short)
        (wall "pandoc gfm→plain (12-line md)" ["/opt/homebrew/bin/pandoc" "-f" "gfm" "-t" "plain" "--wrap=none" "--columns=62"] --rounds 15 --stdin $md)
    ] | fmt | table --width 100)
}

export def main [] { zellij; print ""; sketchybar; print ""; pandoc }
