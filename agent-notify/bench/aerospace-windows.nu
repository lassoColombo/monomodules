#!/usr/bin/env nu
# Can aerospace be a session-container? — plan.md step 12, phase 1.
#
# A PROBE, not a benchmark, and it is here for `bench/`'s own reason: a step
# that measures is a step that can be re-run, and this one has to be re-run on
# any machine that is not this one. Nothing in ../mod.nu imports it. It answers
# the questions step 12 says have to be answered before an interface is worth
# writing, by running aerospace rather than reasoning about it.
#
#   use agent-notify/bench
#   bench aerospace-windows
#
# Read-only. The experiments that needed a window to move about were run once by
# hand and are written up below rather than left behind as a command that opens
# windows on someone's desktop.
#
# ── WHAT IT FOUND, 2026-09-14 ─────────────────────────────────────────────────
#
#   E1  cost        list-windows --all 10.9ms · --focused 13.3ms
#                   list-workspaces --focused 10.2ms · focus --window-id 20.6ms
#   E2  IDENTITY    `--focused` IS NOT THE AGENT'S WINDOW. Caught live: focused
#                   was Firefox on workspace 2 while the agent sat in Ghostty on
#                   workspace 1. This kills "capture the focused window at
#                   session start" — `discover-own-location` caches, so one
#                   wrong answer is wrong forever.
#   E3  durability  a window id SURVIVES a workspace move (5674 stayed 5674)
#   E4  focus       `focus --window-id` reaches a window on another workspace
#                   and SWITCHES to it. 20.6ms. Not a silent no-op.
#   E5  failure     a bogus window id EXITS 1 with a clear stderr — the opposite
#                   of zellij, which exits 0 whatever happens (plan.md §11)
#   E6  index       the terminal window title is `<session> | <active tab>`, so
#                   a window can be found from the `zellij.session` the record
#                   already holds. The session half is ZELLIJ'S OWN, so it does
#                   not depend on our display being enabled (D57)
#
# ── WHAT IT COST TO LEARN, which is a finding of its own ──────────────────────
#
#   `aerospace close --window-id N` EXITS 0 AND DOES NOTHING. The window stays.
#   Focusing it first and calling bare `close` does nothing either. What closed
#   the throwaways was killing their processes.
#
#   `open -na Ghostty.app` starts a SEPARATE APP INSTANCE, not a new window in
#   the running one — so the throwaway had its own pid, and `aerospace` kept
#   listing a window for an instance that had none until the process died. So
#   AEROSPACE CAN LIST WINDOWS THAT ARE NO LONGER THERE, which is the case a
#   jump has to survive (E5 says it fails loudly, which is the good news).
#
# ── WHAT IS STILL UNTESTED ────────────────────────────────────────────────────
#
#   TWO CLIENTS ON ONE ZELLIJ SESSION. Both windows would carry the same title
#   prefix and the match would be ambiguous. Not reproduced here: `open -na`
#   gives a separate app instance, which is not how a second window is made.
#   Lowest-risk mitigation if it bites: first match wins, stable order.
#
#   WHETHER THE TITLE HOLDS WITH OUR DISPLAY OFF. The session half is zellij's
#   own and the tab half is ours, so `<session> | Tab #1` should still match —
#   reasoned, not observed, and it is the claim D57 rests on here.

const AERO = "/opt/homebrew/bin/aerospace"
const TERMINALS = ["Ghostty" "Alacritty" "kitty" "WezTerm" "Terminal" "iTerm2"]

def windows []: nothing -> table {
    ^$AERO list-windows --all --format '%{window-id}|%{app-name}|%{workspace}|%{window-title}'
    | lines
    | each {|l| let p = $l | split row "|"
                {id: ($p | get 0 | str trim), app: ($p | get 1 | str trim)
                 workspace: ($p | get 2 | str trim), title: ($p | skip 3 | str join "|" | str trim)} }
}

def focused []: nothing -> record {
    let r = ^$AERO list-windows --focused --format '%{window-id}' | complete
    if $r.exit_code != 0 { return {} }
    let id = $r.stdout | str trim
    windows | where id == $id | get -o 0 | default {}
}

# THE CANDIDATE MECHANISM, in the four lines it would actually be. Note what it
# does NOT do: discover anything, store anything, or run at paint time.
def window-for-session [session: string]: nothing -> any {
    if ($session | is-empty) { return null }
    windows | where {|w| ($w.app in $TERMINALS) and ($w.title | str starts-with $"($session) ") } | get -o 0
}

def time-it [label: string, closure: closure]: nothing -> record {
    let times = 1..12 | each {|| (timeit { do $closure }) | into int | $in / 1000000 }
    {probe: $label, median_ms: ($times | math median | math round --precision 2)}
}

export def main [] {
    print $"(ansi cyan)── E1. what it costs ─────────────────────────────────(ansi reset)"
    print ([(time-it "list-windows --all"        {|| ^$AERO list-windows --all --format '%{window-id}' | complete })
            (time-it "list-windows --focused"    {|| ^$AERO list-windows --focused --format '%{window-id}' | complete })
            (time-it "list-workspaces --focused" {|| ^$AERO list-workspaces --focused | complete })] | table)

    let zs = $env.ZELLIJ_SESSION_NAME? | default ""
    let here = focused
    let mine = window-for-session $zs

    print $"\n(ansi cyan)── E2. is `--focused` this agent's window? ───────────(ansi reset)"
    print ([{which: "focused right now", id: $here.id?, app: $here.app?, ws: $here.workspace?, title: $here.title?}
            {which: $"titled for session '($zs)'", id: $mine.id?, app: $mine.app?
             ws: $mine.workspace?, title: $mine.title?}] | table)
    let agree = ($mine != null) and ($here.id? == $mine.id?)
    print $"  VERDICT: (if $agree {
        $'(ansi yellow)they agree RIGHT NOW — which proves nothing, see the header(ansi reset)'
      } else {
        $'(ansi red)MISMATCH — `--focused` is not this agent window(ansi reset)'
      })"

    print $"\n(ansi cyan)── E6. finding the window from the record ────────────(ansi reset)"
    print (windows | where app in $TERMINALS | table)
    let matches = if ($zs | is-empty) { [] } else {
        windows | where {|w| ($w.app in $TERMINALS) and ($w.title | str starts-with $"($zs) ") } }
    print $"  windows titled for '($zs)': ($matches | length) — (
        if (($matches | length) == 1) { 'unambiguous' } else { 'AMBIGUOUS or absent' })"

    print $"\n(ansi cyan)── E5. how it fails ──────────────────────────────────(ansi reset)"
    let bogus = ^$AERO focus --window-id 999999 | complete
    print $"  focus --window-id 999999 -> exit ($bogus.exit_code), stderr: ($bogus.stderr | str trim)"
    print $"  (ansi green)loud, unlike zellij, which exits 0 whatever happens(ansi reset)"

    print $"\n(ansi cyan)── what a jump would cost ────────────────────────────(ansi reset)"
    if $mine == null {
        print "  no window found for this session — nothing to price"
    } else {
        print (time-it "resolve + focus (the whole outer rung)" {||
            let w = window-for-session $zs
            if $w != null { ^$AERO focus --window-id $w.id | complete } } | table)
    }
}
