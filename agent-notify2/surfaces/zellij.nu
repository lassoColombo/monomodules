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
# there — no lookup. `settings` collects them, which is why it takes the config
# AND the environment: both are "what this surface needs to know before it
# thinks", and gathering them once is what keeps `project` pure enough to run
# twice per event.
#
# TABS ARE NOT HERE. A tab's name belongs to you, not to us, so a tab title
# cannot be computed from the store alone — it has to be read, stripped and put
# back. That is a different problem with its own answer, and it gets its own step.

use ../core/schema.nu

export const INFO = {name: "zellij", title: "zellij pane titles"}

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

# The config namespace, strictly, plus who and where we are.
#
# Strict HERE rather than in `core/config.nu` because these are our fields: the
# core must never have to learn what a surface's settings look like.
#
# `me` is the id of the agent this event is about, handed down by dispatch — which
# already knows it, and knows it exactly, where asking the environment would be a
# guess. The pane is ours to find: dispatch runs inside the agent's process.
export def settings [given: record, me: any]: nothing -> record {
    for k in ($given | columns | where {|k| $k != "glyphs" }) {
        error make --unspanned {msg: $"zellij: '($k)' is not a setting \(the only one is: glyphs\)"}
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

    { glyphs: ($DEFAULT_GLYPHS | merge $g)
      me: { id: ($me | default "")
            session: ($env.ZELLIJ_SESSION_NAME? | default "")
            pane_id: ($env.ZELLIJ_PANE_ID? | default "") } }
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

# PURE: which panes should say what.
#
# Where a pane comes from, in order: the ENVIRONMENT for the agent we are running
# inside — authoritative, and true before the store has ever heard of this pane —
# and the `zellij` namespace of the record for everybody else, which `apply`
# wrote when that agent last painted itself. An agent in no pane projects to
# nothing, which is how a bare terminal costs zero.
export def project [records: list<record>, settings: record]: nothing -> list<record> {
    let me = $settings.me
    $records
    | each {|r|
        let here = ($me.id | is-not-empty) and ($r.id? == $me.id) and ($me.pane_id | is-not-empty)
        let session = if $here { $me.session } else { $r.zellij?.session? | default "" }
        let pane = if $here { $me.pane_id } else { $r.zellij?.pane_id? | default "" }
        if ($session | is-empty) or ($pane | is-empty) {
            null
        } else {
            # `base` is the title WITHOUT the glyph: what the pane should say once
            # this agent is gone. Carried in the projection so releasing a pane
            # needs no lookup — see `renames`.
            {session: $session, pane_id: $pane
             title: (title-for $r $settings.glyphs)
             base: (base-for $r)}
        }
      }
    | compact
    | sort-by session pane_id
}

# A blank title DROPS our name instead of writing one, so zellij falls back to
# what it would have shown anyway (the running command). A projection with
# nothing to say must never blank a pane.
def rename [session: string, pane_id: string, name: string] {
    if ($name | str trim | is-empty) {
        ^zellij --session $session action undo-rename-pane --pane-id $pane_id | complete | ignore
    } else {
        ^zellij --session $session action rename-pane --pane-id $pane_id $name | complete | ignore
    }
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
# Exactly which panes to write, and what to write on them — as DATA, so the
# decision can be read and asserted without a zellij to rename (D34).
#
# Two kinds. The panes whose title MOVED: the gate proved that something changed,
# but with several agents open most of them did not, and each rename is ~11ms of
# subprocess. And the panes we have RELEASED: an agent that ended must not leave
# its glyph behind, and nothing else would ever clear it, because a pane nobody
# projects onto is a pane nobody touches.
#
# A released pane gets its `base` — the same title with the glyph taken off. NOT
# a blank one, which would mean undo-rename-pane, and undo POPS ONE RENAME off a
# stack rather than clearing our name: after a session's worth of state changes
# it would leave the second-to-last agent title sitting there. Verified the hard
# way on a real pane. Blank still means undo, and is still right for an agent that
# never had a name to show.
export def renames [desired: list<record>, previous: any]: nothing -> list<record> {
    let before = $previous | default []
    let moved = $desired | where {|p|
        let was = $before | where {|b| ($b.session == $p.session) and ($b.pane_id == $p.pane_id) } | get -o 0
        ($was == null) or ($was.title != $p.title)
    }
    let released = $before
        | where {|b| not ($desired | any {|p| ($p.session == $b.session) and ($p.pane_id == $b.pane_id) }) }
        | each {|b| {session: $b.session, pane_id: $b.pane_id, title: ($b.base? | default "")} }
    $moved ++ $released
}

export def apply [desired: list<record>, previous: any, settings: record]: nothing -> any {
    for r in (renames $desired $previous) {
        try { rename $r.session $r.pane_id $r.title }
    }
    let me = $settings.me
    if ($me.pane_id | is-empty) { null } else { {zellij: {session: $me.session, pane_id: $me.pane_id}} }
}
