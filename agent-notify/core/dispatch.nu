# What changed, and whether it is worth telling anyone.
#
# THE DIVISION OF LABOUR, which is the whole point of this file:
#
#   a display    DESCRIBES — `render-items` returns a map of key → what that key
#                should show. It never works out what moved.
#   dispatch     DECIDES — it holds two of those maps, one for the store as it
#                was and one for the store as it is, and diffs them. Once,
#                correctly, for every display that will ever exist.
#   the session-store    holds facts, and is the only thing anybody writes.
#
# THE GATE falls out of the diff rather than being a separate idea: no key
# changed and none disappeared means there is nothing to say, so nothing is
# sent. A `Stop` changes an agent's message, but a pane title has no message in
# it and a counter is a number — both maps come back identical and no subprocess
# runs.
#
# AND THE DIFF IS PER KEY. With four agents open, a state change moves one pane
# title; the other three keys are unchanged and are never written. A display
# used to have to work that out for itself, and zellij's hand-rolled version of
# it is what this replaces.
#
# REMOVED KEYS CARRY THEIR OLD VALUE, because undoing needs to know what was
# there. A pane cannot be handed back by its id alone — it needs the name to put
# back once the glyph comes off.
#
# TWO SNAPSHOTS, NOT A DELTA. Callers pass the whole session-store before and
# after, so there is one spelling for "what was there a moment ago" whether the
# change came from a hook (one record moved) or from the prune-daemon (some
# records were pruned).
#
# WHY IT RUNS INSIDE THE AGENT'S PROCESS: the hook already has the environment a
# display may need to see — which is what `discover-own-location` is for — and
# the session-store in hand. A daemon would have to be told both.
#
# NOTHING HERE MAY THROW. It runs after the session-store has committed. Each
# display is wrapped alone, so one failing cannot stop the next, and a broken
# config degrades to "no displays" rather than to a broken hook.

use config.nu
use session-store.nu
use current-session.nu
use ../integrations/zellij
use ../integrations/sketchybar

# ── the integration-registry displays ─────────────────────────────────────────
# One entry per display, written by hand because nushell has no first-class
# modules. `discover-own-location` is optional: only a display that can see
# something about its own process needs it.
export def integration-registry []: nothing -> record {
    { zellij: {info: $zellij.INFO
               settings: {|given| zellij settings $given }
               discover-own-location: {|stored, settings| zellij discover-own-location $stored $settings }
               render-items: {|records, settings| zellij render-items $records $settings }
               push-items: {|changed, removed, settings| zellij push-items $changed $removed $settings }}
      sketchybar: {info: $sketchybar.INFO
                   settings: {|given| sketchybar settings $given }
                   render-items: {|records, settings| sketchybar render-items $records $settings }
                   push-items: {|changed, removed, settings| sketchybar push-items $changed $removed $settings }} }
}

export def integration-registry-names []: nothing -> list<string> { integration-registry | columns }

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

def display-verdict [name: string, action: string, wrote: int, undid: int, why: string]: nothing -> record {
    {display: $name, action: $action, wrote: $wrote, undid: $undid, why: $why}
}

# Repaint every enabled display from two snapshots of the session-store.
#
# `--force` writes every key whether or not it moved — the recovery command
# after a config edit, and what the prune-daemon uses. It does NOT mean "there
# was nothing before": removals are still worked out from `before`, which is how
# an agent the prune-daemon has just pruned gets its pane handed back.
export def repaint [
    before: list<record>    # the session-store as it was
    after: list<record>     # the session-store as it is
    --force                 # write every key, not only the ones that moved
    --table: record         # override the integration-registry displays (tests)
]: nothing -> list<record> {
    let displays = $table | default (integration-registry)
    if ($displays | is-empty) { return [] }

    let cfg = config load
    let asked = $cfg.displays? | default []
    let on = if (($asked | describe) | str starts-with "list") {
        $asked | where {|n| $n in ($displays | columns) }
    } else { [] }
    if ($on | is-empty) { return [] }

    # Which agent's environment this is. Only `discover-own-location` needs it,
    # and only a command typed about some OTHER agent makes it differ from the
    # subject of the change — for a hook they are the same.
    let who = try { current-session resolve } catch { null }
    let me = if ($who == null) { "" } else { $who.id? | default "" }

    $on | each {|name|
        let display = $displays | get $name
        try {
            # The DISPLAY half of this tool's namespace, plus whatever it shares
            # with its command half. A tool's commands are not dispatched to and
            # are not configured from here — see core/config.nu.
            let settings = do $display.settings (config settings-for $cfg $name "display")

            # What this process can see about itself that the session-store does
            # not know yet — which pane it is in, say. Recorded in the display's
            # own namespace, and folded into the snapshot so that `render-items`
            # can stay a plain function of records. `patch` commits nothing when
            # the facts are unchanged, so the steady state is a read and a
            # comparison.
            let seen = if ($display.discover-own-location? == null) or ($me | is-empty) { {} } else {
                # Handed what the session-store already holds for this display,
                # so it can skip a lookup it has already paid for.
                let mine = $after | where {|r| $r.id? == $me } | get -o 0
                let stored = if ($mine == null) { {} } else { $mine | get -o $name | default {} }
                let facts = do $display.discover-own-location $stored $settings
                if (($facts | describe) | str starts-with "record") { $facts } else { {} }
            }
            let now = if ($seen | is-empty) { $after } else {
                session-store patch $me {($name): $seen} | ignore
                $after | each {|r|
                    if ($r.id? != $me) { $r } else {
                        $r | upsert $name (($r | get -o $name | default {}) | merge $seen)
                    }
                }
            }

            let delta = diff (do $display.render-items $before $settings) (do $display.render-items $now $settings)
            if (not $force) and ($delta.changed | is-empty) and ($delta.removed | is-empty) {
                display-verdict $name "skipped" 0 0 ""
            } else {
                let write = if $force { do $display.render-items $now $settings } else { $delta.changed }
                do $display.push-items $write $delta.removed $settings
                display-verdict $name "applied" ($write | columns | length) ($delta.removed | columns | length) ""
            }
        } catch {|e| display-verdict $name "failed" 0 0 $e.msg }
    }
}
