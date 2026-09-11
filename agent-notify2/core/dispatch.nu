# Telling the surfaces that something happened — and, far more often, working out
# that nothing worth telling them happened at all.
#
# THE GATE. A surface is a pure function from the store to what should be on
# screen, plus an impure half that puts it there. So before touching anything we
# run the pure half TWICE: once against the store as it was, once as it is. If the
# two agree, the screen would not change, and we stop.
#
#     project(before) == project(after)   →  do nothing
#
# That one comparison is the whole performance story. A `Stop` changes `message`,
# but a zellij pane title has no message in it, so the projection is identical and
# zellij — 11ms of subprocess — is never called. v1 reached the same place with a
# bash fast-path gate, a separate rule for SketchyBar and a janitor to re-check;
# here it is a property every future surface inherits for free, with no cache, no
# TTL and nothing remembered between events.
#
# WHY IT RUNS INSIDE THE AGENT'S PROCESS. The hook already has what a surface
# needs: the agent's environment. That is how the zellij surface will learn which
# pane it is in — `$env.ZELLIJ_PANE_ID` is simply there — without the core ever
# hearing the word zellij. A daemon would have to be told.
#
# WHY THE SURFACES ARE A TABLE OF CLOSURES. `use` is parse-time and nushell has no
# first-class modules, so a name cannot be turned into a module at runtime. The
# `shipped` table is written once, by hand, with one entry per surface; passing a
# different table is what lets the tests exercise all of this with nothing
# installed.
#
# NOTHING HERE MAY THROW. It runs after the store has already committed, on the
# path of every tool call. Each surface is wrapped on its own, so zellij failing
# cannot stop the bar, and a broken config means "no surfaces" rather than a
# broken hook (core/config.nu explains that trade).

use config.nu
use store.nu
use ../surfaces/zellij.nu

# ── the shipped surfaces ─────────────────────────────────────────────────────
# Step 5 adds SketchyBar here. Each entry is four things: what it is, how it reads
# its own settings, the pure projection, and the side effect.
export def shipped []: nothing -> record {
    { zellij: {info: $zellij.INFO
               settings: {|given, me| zellij settings $given $me }
               project: {|recs, s| zellij project $recs $s }
               apply: {|desired, s| zellij apply $desired $s }} }
}

export def known []: nothing -> list<string> { shipped | columns }

# Project the store onto every enabled surface, skipping the ones whose output
# would not change. Returns what it did, per surface, so a human can ask.
#
# `--force` skips the gate and repaints everything: the recovery command after a
# config edit, and what a periodic trigger will call.
#
# Named `project`, not `run`: `run` is a PARSER KEYWORD and cannot be a command
# name at all — a different failure from builtin shadowing, and a louder one (§10).
export def project [
    before: any = null      # the record as it was, or null if it is new
    after: any = null       # the record as it is, or null if it was dropped
    --table: record         # override the shipped surfaces (tests)
    --force                 # repaint even when the projection is unchanged
]: nothing -> list<record> {
    let surfaces = $table | default (shipped)
    if ($surfaces | is-empty) { return [] }

    let cfg = config load
    let asked = ($cfg.surfaces? | default [])
    let on = if (($asked | describe) | str starts-with "list") {
        $asked | where {|n| $n in ($surfaces | columns) }
    } else { [] }
    if ($on | is-empty) { return [] }

    let me = ($after | default $before | get -o id)
    let now = store list | sort-by id
    let was = if $force { null } else {
        if $me == null { return [] }
        (($now | where id != $me) ++ (if $before == null { [] } else { [$before] })) | sort-by id
    }

    $on | each {|name|
        let s = $surfaces | get $name
        try {
            let settings = do $s.settings ($cfg | get -o $name | default {}) $me
            let desired = do $s.project $now $settings
            if (not $force) and ((do $s.project $was $settings) == $desired) {
                {surface: $name, action: "skipped"}
            } else {
                # A surface never writes the store. It may REPORT what it learned
                # about this agent — where its pane is, which item it was given —
                # and that is recorded here, in its own namespace, by the one
                # module that owns writing. `patch` commits nothing when the facts
                # are unchanged, so the steady state is a read and a comparison.
                let learned = do $s.apply $desired $settings
                if ($me != null) and (($learned | describe) | str starts-with "record") {
                    store patch $me $learned | ignore
                }
                {surface: $name, action: "applied"}
            }
        } catch {|e|
            {surface: $name, action: "failed", why: $e.msg}
        }
    }
}
