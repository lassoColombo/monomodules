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

    { binary: (resolve-binary ($given.binary? | default ""))
      glyphs: ($DEFAULT_GLYPHS | merge $g) }
}

# What this process can see about itself: which pane it is running in. Empty when
# we are not in zellij at all, which is how a bare terminal costs nothing.
export def observe []: nothing -> record {
    let session = $env.ZELLIJ_SESSION_NAME? | default ""
    let pane = $env.ZELLIJ_PANE_ID? | default ""
    if ($session | is-empty) or ($pane | is-empty) { {} } else { {session: $session, pane_id: $pane} }
}

# The title one record deserves. Empty means "we have nothing to say", which
# `apply` turns into dropping our name rather than writing a blank one.
# An ABSOLUTE path to the program, because a hook's PATH is not your shell's PATH
# and a LAUNCHD JOB's is smaller still: the clock runs with /usr/bin:/bin and
# nothing else, so a bare `^zellij` silently does nothing there. Resolved once, in
# `settings`, so a missing program is a loud configuration error rather than a
# surface that reports "applied" and paints nothing — which is exactly how this
# was found.
# No `-> string` signature: a def annotated that way cannot END in `error make`
# (§10).
def resolve-binary [given: string] {
    if ($given | is-not-empty) {
        if not ($given | path exists) {
            error make --unspanned {msg: $"zellij: no program at '($given)'"}
        }
        return $given
    }
    let found = which "zellij" | get -o 0.path | default ""
    if ($found | is-not-empty) { return $found }
    for d in ["/opt/homebrew/bin" "/usr/local/bin" "/usr/bin"] {
        let p = $d | path join "zellij"
        if ($p | path exists) { return $p }
    }
    error make --unspanned {msg: ("zellij: not found. Set `zellij.binary: <path>` in the config "
        + "file if it lives somewhere unusual.")}
}

def base-for [rec: record]: nothing -> string {
    let named = $rec.name? | default "" | str trim
    if ($named | is-not-empty) { $named } else { $rec.cwd? | default "" | path basename }
}

def title-for [rec: record, glyphs: record]: nothing -> string {
    let glyph = $glyphs | get -o ($rec.state? | default "idle") | default ""
    [$glyph (base-for $rec)] | where {|x| $x | is-not-empty } | str join " "
}

# PURE: which pane should say what, keyed by pane.
#
# The key is only an identity for dispatch to diff on — everything apply needs is
# in the value. `base` is the title WITHOUT the glyph: what the pane should say
# once this agent is gone, carried here so that releasing one needs no lookup.
#
# An agent whose pane the store does not know projects to nothing, which is how a
# bare terminal, and an agent that has not painted yet, both cost zero.
export def project [records: list<record>, settings: record]: nothing -> record {
    mut out = {}
    for r in $records {
        let session = $r.zellij?.session? | default ""
        let pane = $r.zellij?.pane_id? | default ""
        if ($session | is-not-empty) and ($pane | is-not-empty) {
            $out = ($out | upsert $"($session)|($pane)" {
                session: $session, pane_id: $pane
                title: (title-for $r $settings.glyphs)
                base: (base-for $r)
            })
        }
    }
    $out
}

# A blank title DROPS our name instead of writing one, so zellij falls back to
# what it would have shown anyway (the running command). A projection with
# nothing to say must never blank a pane.
def argv [binary: string, session: string, pane_id: string, name: string]: nothing -> list<string> {
    if ($name | str trim | is-empty) {
        [$binary "--session" $session "action" "undo-rename-pane" "--pane-id" $pane_id]
    } else {
        [$binary "--session" $session "action" "rename-pane" "--pane-id" $pane_id $name]
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
    let writes = $changed | columns | each {|k|
        let p = $changed | get $k
        argv $settings.binary $p.session $p.pane_id $p.title
    }
    let undos = $removed | columns | each {|k|
        let p = $removed | get $k
        argv $settings.binary $p.session $p.pane_id ($p.base? | default "")
    }
    $writes ++ $undos
}

export def apply [changed: record, removed: record, settings: record]: nothing -> nothing {
    for c in (commands $changed $removed $settings) {
        try { ^($c | first) ...($c | skip 1) | complete | ignore }
    }
}
