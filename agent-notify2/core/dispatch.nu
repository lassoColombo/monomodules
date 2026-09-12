# What changed, and whether it is worth telling anyone.
#
# THE DIVISION OF LABOUR, which is the whole point of this file:
#
#   a surface    DESCRIBES — `project` returns a map of key → what that key
#                should show. It never works out what moved.
#   dispatch     DECIDES — it holds two of those maps, one for the store as it
#                was and one for the store as it is, and diffs them. Once,
#                correctly, for every surface that will ever exist.
#   the store    holds facts, and is the only thing anybody writes.
#
# THE GATE falls out of the diff rather than being a separate idea: no key
# changed and none disappeared means there is nothing to say, so nothing is sent.
# A `Stop` changes an agent's message, but a pane title has no message in it and a
# counter is a number — both maps come back identical and no subprocess runs.
#
# AND THE DIFF IS PER KEY. With four agents open, a state change moves one pane
# title; the other three keys are unchanged and are never written. A surface used
# to have to work that out for itself, and zellij's hand-rolled version of it is
# what this replaces.
#
# REMOVED KEYS CARRY THEIR OLD VALUE, because undoing needs to know what was
# there. A pane cannot be handed back by its id alone — it needs the name to put
# back once the glyph comes off.
#
# TWO SNAPSHOTS, NOT A DELTA. Callers pass the whole store before and after, so
# there is one spelling for "what was there a moment ago" whether the change came
# from a hook (one record moved) or from the clock (some records were pruned).
#
# WHY IT RUNS INSIDE THE AGENT'S PROCESS: the hook already has the environment a
# surface may need to see — which is what `observe` is for — and the store in
# hand. A daemon would have to be told both.
#
# NOTHING HERE MAY THROW. It runs after the store has committed. Each surface is
# wrapped alone, so one failing cannot stop the next, and a broken config degrades
# to "no surfaces" rather than to a broken hook.

use config.nu
use store.nu
use identity.nu
use ../surfaces/zellij.nu
use ../surfaces/sketchybar

# ── the shipped surfaces ─────────────────────────────────────────────────────
# One entry per surface, written by hand because nushell has no first-class
# modules. `observe` is optional: only a surface that can see something about its
# own process needs it.
export def shipped []: nothing -> record {
    { zellij: {info: $zellij.INFO
               settings: {|given| zellij settings $given }
               observe: {|known, s| zellij observe $known $s }
               project: {|recs, s| zellij project $recs $s }
               apply: {|changed, removed, s| zellij apply $changed $removed $s }}
      sketchybar: {info: $sketchybar.INFO
                   settings: {|given| sketchybar settings $given }
                   project: {|recs, s| sketchybar project $recs $s }
                   apply: {|changed, removed, s| sketchybar apply $changed $removed $s }} }
}

export def known []: nothing -> list<string> { shipped | columns }

# Two maps in, two maps out: what to write, and what to undo.
def diff [had: record, want: record]: nothing -> record {
    let want_keys = $want | columns
    mut changed = {}
    for k in $want_keys {
        if ($had | get -o $k) != ($want | get $k) { $changed = ($changed | upsert $k ($want | get $k)) }
    }
    mut removed = {}
    for k in ($had | columns) {
        if ($k not-in $want_keys) { $removed = ($removed | upsert $k ($had | get $k)) }
    }
    {changed: $changed, removed: $removed}
}

def verdict [name: string, action: string, wrote: int, undid: int, why: string]: nothing -> record {
    {surface: $name, action: $action, wrote: $wrote, undid: $undid, why: $why}
}

# Project two snapshots of the store onto every enabled surface.
#
# `--force` writes every key whether or not it moved — the recovery command after
# a config edit, and what the clock uses. It does NOT mean "there was nothing
# before": removals are still worked out from `before`, which is how an agent the
# clock has just pruned gets its pane handed back.
export def project [
    before: list<record>    # the store as it was
    after: list<record>     # the store as it is
    --force                 # write every key, not only the ones that moved
    --table: record         # override the shipped surfaces (tests)
]: nothing -> list<record> {
    let surfaces = $table | default (shipped)
    if ($surfaces | is-empty) { return [] }

    let cfg = config load
    let asked = $cfg.surfaces? | default []
    let on = if (($asked | describe) | str starts-with "list") {
        $asked | where {|n| $n in ($surfaces | columns) }
    } else { [] }
    if ($on | is-empty) { return [] }

    # Which agent's environment this is. Only `observe` needs it, and only a
    # command typed about some OTHER agent makes it differ from the subject of the
    # change — for a hook they are the same.
    let who = try { identity resolve } catch { null }
    let me = if ($who == null) { "" } else { $who.id? | default "" }

    $on | each {|name|
        let s = $surfaces | get $name
        try {
            let settings = do $s.settings ($cfg | get -o $name | default {})

            # What this process can see about itself that the store does not know
            # yet — which pane it is in, say. Recorded in the surface's own
            # namespace, and folded into the snapshot so that `project` can stay a
            # plain function of records. `patch` commits nothing when the facts are
            # unchanged, so the steady state is a read and a comparison.
            let seen = if ($s.observe? == null) or ($me | is-empty) { {} } else {
                # Handed what the store already holds for this surface, so it can
                # skip a lookup it has already paid for.
                let mine = $after | where {|r| $r.id? == $me } | get -o 0
                let known = if ($mine == null) { {} } else { $mine | get -o $name | default {} }
                let f = do $s.observe $known $settings
                if (($f | describe) | str starts-with "record") { $f } else { {} }
            }
            let now = if ($seen | is-empty) { $after } else {
                store patch $me {($name): $seen} | ignore
                $after | each {|r|
                    if ($r.id? != $me) { $r } else {
                        $r | upsert $name (($r | get -o $name | default {}) | merge $seen)
                    }
                }
            }

            let d = diff (do $s.project $before $settings) (do $s.project $now $settings)
            if (not $force) and ($d.changed | is-empty) and ($d.removed | is-empty) {
                verdict $name "skipped" 0 0 ""
            } else {
                let write = if $force { do $s.project $now $settings } else { $d.changed }
                do $s.apply $write $d.removed $settings
                verdict $name "applied" ($write | columns | length) ($d.removed | columns | length) ""
            }
        } catch {|e| verdict $name "failed" 0 0 $e.msg }
    }
}
