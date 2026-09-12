# zellij pane titles. The first real surface, and the smallest useful one.
#
#     monomodules                 idle — just the name
#      monomodules               working
#      monomodules               your turn
#
# WHAT IT COSTS, which is the whole reason it looks like this:
#
#   nothing visible changed   0 calls to zellij   (the gate in core/dispatch.nu)
#   a state change            1 call              (~11ms, the rename)
#
# v1 spent three calls on the same event: one to ask zellij where the pane was
# and what it was called, one to rename the pane, one to rename the tab. Two of
# those are gone here, for two different reasons.
#
# THE FIRST: WE NEVER READ A TITLE BACK. v1 recovered a pane's name by reading
# its current title and stripping our glyph off the front — sixty lines of
# parsing, plus a list of old glyphs we no longer write but must still recognise.
# v2 needs none of it, because the NAME IS A FACT AND FACTS LIVE IN THE STORE:
# `agent-notify2 name "monomodules"`, or the last component of the cwd when
# nobody said otherwise. The title is computed, never parsed. The price is that
# renaming a pane by hand gets overwritten on the next state change, which is the
# right trade when the store is the source of truth.
#
# THE SECOND: WE ALREADY KNOW WHERE WE ARE. Dispatch runs inside the agent's own
# process, so `$env.ZELLIJ_SESSION_NAME` and `$env.ZELLIJ_PANE_ID` are simply
# there — no lookup. That is what `observe` reports, and dispatch writes it into
# this surface's namespace on the record before projecting. So `project` never
# reads the environment and never has to ask "is this record me?": by the time it
# runs, where we are is just another fact in the store.
#
# TABS. A tab shows one glyph per agent living in it, in front of its own name:
#
#      root        one agent working
#      root      one working, one waiting
#
# A tab's name is not ours, so it has to be read at least once. The cost is kept
# to ONCE PER SESSION by folding it into the read we already need: the environment
# says which PANE we are in but not which TAB, so `observe` runs one `list-panes`
# the first time — and that same call returns the tab's name. Both are recorded,
# and after that a tab title is computed from the store like everything else.
#
# The price is that a tab renamed LATER is overwritten on the next state change,
# the same bargain already struck for pane names: the store owns the name.

use ../../core/schema.nu
use program.nu

export const INFO = {name: "zellij", title: "zellij pane and tab titles"}

# Nerd Font (Font Awesome BMP), chosen so the states are told apart by SHAPE: a
# zellij title carries no colour, so the shape has to do the whole job.
#   f021 ↻ circular arrows  turning, in progress
#   f075 speech bubble      the agent is talking to you
#   f071 warning triangle   blocked, needs a hand
# `idle` is empty on purpose: a quiet agent shows its name and nothing else.
# Written as ESCAPES, not as literal characters: these live in the Unicode
# Private Use Area, where a great deal of tooling quietly drops them — which is
# exactly what happened the first time this file was written, and the tests
# caught it as "every state has the same title".
const DEFAULT_GLYPHS = {
    working: "\u{f021}"           # circular arrows — turning, in progress
    awaiting: "\u{f075}"          # speech bubble — the agent is talking to you
    needs-attention: "\u{f071}"   # warning triangle — blocked, needs a hand
    idle: ""                      # nothing: a quiet agent shows only its name
}

# The config namespace, strictly. Nothing else — where we are is `observe`'s job.
#
# Strict HERE rather than in `core/config.nu` because these are our fields: the
# core must never have to learn what a surface's settings look like.
export def settings [given: record]: nothing -> record {
    for k in ($given | columns | where {|k| $k not-in ["glyphs" "binary"] }) {
        error make --unspanned {msg: $"zellij: '($k)' is not a setting \(try: glyphs, binary\)"}
    }
    let g = $given.glyphs? | default {}
    if not (($g | describe) | str starts-with "record") {
        error make --unspanned {msg: $"zellij: `glyphs` must be a map of state → glyph, got ($g | describe)"}
    }
    for k in ($g | columns) {
        if ($k not-in $schema.STATES) {
            error make --unspanned {msg: $"zellij: '($k)' is not a state \(want one of: ($schema.STATES | str join ', ')\)"}
        }
        if (($g | get $k | describe) != "string") {
            error make --unspanned {msg: $"zellij: the glyph for '($k)' must be a string"}
        }
    }

    { binary: (program resolve ($given.binary? | default ""))
      glyphs: ($DEFAULT_GLYPHS | merge $g) }
}

# Remove a leading run of our own glyphs from a title. The only place stripping
# happens — once, when a tab's name is first learned, rather than on every write
# as v1 did. A title that is glyphs and nothing else strips to "", which is our
# own leftover and not a name.
def strip-glyphs [name: string, glyphs: record]: nothing -> string {
    let marks = $glyphs | values | where {|g| ($g | str trim) != "" }
    $name | str trim | split row " " | skip while {|t| $t in $marks } | str join " " | str trim
}

def pane-info [binary: string, session: string, pane: string]: nothing -> any {
    let r = try { ^$binary --session $session action list-panes -t -j | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) { return null }
    let ps = try { $r.stdout | from json } catch { null }
    if $ps == null { return null }
    $ps | where {|p| ($p.id | into string) == $pane } | get -o 0
}

# What this process can see about itself. Empty when we are not in zellij at all,
# which is how a bare terminal costs nothing.
#
# `known` is what the store already holds for us, and it exists so this can be
# CHEAP: the environment gives the pane for free, but the tab needs a
# `list-panes` — so that call is made only when the tab is unknown or the pane has
# moved. Once per session, the same shape as the pid walk. The same call also
# returns the tab's NAME, which is why a tab title never has to be read again.
export def observe [known: record, settings: record]: nothing -> record {
    let session = $env.ZELLIJ_SESSION_NAME? | default ""
    let pane = $env.ZELLIJ_PANE_ID? | default ""
    if ($session | is-empty) or ($pane | is-empty) { return {} }

    let here = {session: $session, pane_id: $pane}
    # Bound in two, because a boolean expression does not continue across lines
    # with the operator at either end (§10).
    let same_pane = (($known.session? | default "") == $session) and (($known.pane_id? | default "") == $pane)
    if $same_pane and ($known.tab_id? != null) { return $here }

    let info = pane-info $settings.binary $session $pane
    if $info == null { return $here }
    $here | merge {
        tab_id: ($info.tab_id | into string)
        tab_base: (strip-glyphs ($info.tab_name? | default "") $settings.glyphs)
    }
}

# The title one record deserves. Empty means "we have nothing to say", which
# `apply` turns into dropping our name rather than writing a blank one.

def base-for [rec: record]: nothing -> string {
    let named = $rec.name? | default "" | str trim
    if ($named | is-not-empty) { $named } else { $rec.cwd? | default "" | path basename }
}

def title-for [rec: record, glyphs: record]: nothing -> string {
    let glyph = $glyphs | get -o ($rec.state? | default "idle") | default ""
    [$glyph (base-for $rec)] | where {|x| $x | is-not-empty } | str join " "
}

# PURE: what every pane and every tab should say.
#
# Two kinds of key, and the value carries everything `apply` needs — the key is
# only an identity for dispatch to diff on. `base` is the title WITHOUT the
# glyphs: what the pane or tab should say once its agents are gone, carried here
# so that releasing one needs no lookup.
#
# An agent whose pane the store does not know projects to nothing, which is how a
# bare terminal, and an agent that has not painted yet, both cost zero.
export def project [records: list<record>, settings: record]: nothing -> record {
    mut out = {}

    for r in $records {
        let session = $r.zellij?.session? | default ""
        let pane = $r.zellij?.pane_id? | default ""
        if ($session | is-not-empty) and ($pane | is-not-empty) {
            $out = ($out | upsert $"pane|($session)|($pane)" {
                kind: "pane", session: $session, pane_id: $pane
                title: (title-for $r $settings.glyphs)
                base: (base-for $r)
            })
        }
    }

    # One glyph per agent, most urgent first, in front of the tab's own name.
    let placed = $records | where {|r|
        (($r.zellij?.session? | default "") != "") and ($r.zellij?.tab_id? != null)
    }
    for t in ($placed | each {|r| $"($r.zellij.session)|($r.zellij.tab_id)" } | uniq) {
        let members = $placed | where {|r| $"($r.zellij.session)|($r.zellij.tab_id)" == $t }
        let glyphs = aggregate $members $settings.glyphs
        # Two agents in one tab could disagree about its name, but only if it was
        # renamed between them starting. Lowest id wins: arbitrary, and stable, so
        # the title cannot flicker between two answers.
        let named = $members | sort-by id | where {|m| ($m.zellij.tab_base? | default "") != "" } | get -o 0
        let base = if ($named == null) { "" } else { $named.zellij.tab_base }
        let first = $members | first
        $out = ($out | upsert $"tab|($t)" {
            kind: "tab", session: $first.zellij.session, tab_id: $first.zellij.tab_id
            title: ([$glyphs $base] | where {|x| $x | is-not-empty } | str join " ")
            base: $base
        })
    }

    $out
}

# The glyphs a tab wears: one per agent that has something to say, ordered by
# urgency so the line reads the same way every time — which also keeps the diff
# from firing on a reordering that means nothing.
def aggregate [members: list<record>, glyphs: record]: nothing -> string {
    let order = ["needs-attention" "awaiting" "working"]
    $order
    | each {|state|
        let g = $glyphs | get -o $state | default ""
        if ($g | is-empty) { [] } else {
            $members | where {|m| ($m.state? | default "idle") == $state } | each {|_| $g }
        }
      }
    | flatten
    | str join " "
}

# A blank name means UNDO rather than writing an empty title, so zellij falls back
# to what it would have shown anyway.
def argv [binary: string, v: record, name: string]: nothing -> list<string> {
    let tab = $v.kind == "tab"
    let verb = if ($name | str trim | is-empty) {
        if $tab { "undo-rename-tab" } else { "undo-rename-pane" }
    } else {
        if $tab { "rename-tab" } else { "rename-pane" }
    }
    let flag = if $tab { "--tab-id" } else { "--pane-id" }
    let id = if $tab { $v.tab_id } else { $v.pane_id }
    let head = [$binary "--session" $v.session "action" $verb $flag $id]
    if ($name | str trim | is-empty) { $head } else { $head ++ [$name] }
}

# The only impure half — and it does NOT touch the store. A surface reports what
# it learned and dispatch records it; that keeps "the store is the core, surfaces
# read it" true without exception, and keeps this file a LEAF of the import tree,
# which is worth about 2.5ms on every event (§10: a module reached by two import
# paths is parsed twice).
#
# What it learns is where this agent lives, and it matters because a repaint
# started from outside zellij — `agent-notify2 surfaces refresh`, run from the bar
# — has no environment to read and can only find a pane if the store remembers it.
#
# No title is read back before writing. The gate in core/dispatch.nu has already
# established that the projection changed; asking zellij to confirm would cost a
# second subprocess to learn something we decided ourselves.
# Write what moved; hand back what we no longer own.
#
# A released pane gets its `base` — the same title with the glyph taken off. NOT a
# blank one, which would mean undo-rename-pane, and undo POPS ONE RENAME off a
# stack rather than clearing our name: after a session's worth of state changes it
# would leave the second-to-last agent title sitting there. Verified the hard way
# on a real pane. A blank still means undo, and is still right for an agent that
# never had a name to show.
#
# No title is read back before writing. Dispatch has already established which
# keys moved; asking zellij to confirm would cost a subprocess to learn something
# we decided ourselves.
# As DATA first — one argv per pane — so what would be run can be read and
# asserted without a zellij to rename (D34), exactly as SketchyBar's `message` is.
export def commands [changed: record, removed: record, settings: record]: nothing -> list<list<string>> {
    let writes = $changed | columns | each {|k| argv $settings.binary ($changed | get $k) ($changed | get $k | get title) }
    let undos = $removed | columns | each {|k| argv $settings.binary ($removed | get $k) (($removed | get $k).base? | default "") }
    $writes ++ $undos
}

export def apply [changed: record, removed: record, settings: record]: nothing -> nothing {
    for c in (commands $changed $removed $settings) {
        try { ^($c | first) ...($c | skip 1) | complete | ignore }
    }
}
