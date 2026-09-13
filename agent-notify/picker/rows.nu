# Records in, rows out — and what is still possible once the list moves.
#
# PURE, all three of them. No terminal, no zellij, no session-store: hand them
# data and they hand data back, which is what lets the suite assert a whole
# picker without anything installed (D34, the same split as the bar's `message`
# and zellij's `commands`).
#
# ── A ROW ─────────────────────────────────────────────────────────────────────
#
#   {id:    "6923c0bc-…"        the agent, and the SELECTION KEY — see `keep-in-view`
#    state: "awaiting"
#    name:  "monomodules"
#    place: "home/root"         from the locator; "" when nothing claims it
#    match: "awaiting monomodules home/root"
#    rec:   {…}                 the record, for the locator and for the caller
#    via:   {info, owns, location-label, go} | null}
#
# `match` IS EXACTLY WHAT THE ROW SHOWS, and it was not always: the first
# version folded the agent's last message in too, so that a phrase you
# remembered would find it. Running it settled the question in one keystroke. An
# agent's message is prose — several kilobytes of it — so a two-letter query
# matched an agent with no `sn` anywhere on its row, at character 4195 of
# something it said an hour ago. A row that stays for an invisible reason reads
# as a broken filter, and short queries stop narrowing anything at all.
#
# So the filter can only match what you can see. Nothing is lost that matters:
# the preview already shows what the selected agent is saying, in full and live.

use locators.nu

# Most urgent first — the only order a fleet list can be in. Idle sorts LAST
# rather than being hidden: an agent you have finished with is still one you may
# want to go back to.
const URGENCY = ["needs-attention" "awaiting" "working" "idle"]

def rank [state: string]: nothing -> int {
    $URGENCY | enumerate | where item == $state | get -o 0.index | default ($URGENCY | length)
}

# What to call an agent: what it called itself, else the directory it is in,
# else enough of its id to tell it from the others.
def label-of [rec: record]: nothing -> string {
    let name = $rec.name? | default "" | str trim
    if ($name | is-not-empty) { return $name }
    let dir = $rec.cwd? | default "" | path basename
    if ($dir | is-not-empty) { $dir } else { $rec.id? | default "" | str substring 0..7 }
}

# One line, no runs of whitespace — a name or a place carrying a tab or a stray
# newline must not turn into a query nobody can type.
def flatten-text [text: string]: nothing -> string {
    $text | str replace --all --regex '\s+' " " | str trim
}

# `table` is OPTIONAL and the default is resolved HERE, not by the caller. An
# empty record is a perfectly good table meaning "nothing claims anything" — it
# is how the unclaimed case is tested — and `{}` is not null, so `default` would
# never fire on it (§10). Spelling "use the integration-registry locators" as
# `{}` would have meant a picker that silently shows no places and no live
# previews, which is exactly what it did until this was found by running it.
export def build [records: list<record>, table?: record]: nothing -> list<record> {
    let t = $table | default (locators integration-registry)
    $records
    | each {|r|
        let via = locators owner $r --table $t
        let state = $r.state? | default "idle"
        let name = label-of $r
        let location_label = if ($via == null) { "" } else { try { do $via.location-label $r } catch { "" } }
        { id: ($r.id? | default "")
          state: $state
          name: $name
          location-label: $location_label
          match: (flatten-text $"($state) ($name) ($location_label)" | str lowercase)
          rec: $r
          via: $via }
      }
    | sort-by {|c| rank $c.state } {|c| $c.location-label } {|c| $c.name }
}

# The filter. Case-insensitive substring, and nothing cleverer on purpose: a
# substring is PREDICTABLE, and a fleet is small enough that fuzzy matching
# would buy ranking nobody asked for at the cost of code nobody can debug.
#
# THIS NAME SHADOWS THE BUILTIN `filter` FOR THIS FILE (§10), which is why
# everything below reaches for `where` instead. Callers are unaffected — they
# say `rows filter` — and the trap is only ever one file wide, but it is a trap,
# so it is written down here rather than discovered.
export def filter [rows: list<record>, query: string]: nothing -> list<record> {
    let q = $query | str trim | str lowercase
    if ($q | is-empty) { return $rows }
    $rows | where {|r| $r.match | str contains $q }
}

# What is still possible. Run AFTER the list is rebuilt and BEFORE it is drawn.
#
# THE SELECTION IS AN AGENT ID, NEVER AN INDEX, and this is the function that
# makes that pay. The list is live — the session-store is re-read every frame,
# for 0.33ms — so an agent changing state RE-SORTS the list while you are
# looking at it. An index would leave your cursor pointing at whoever slid into
# that slot, and you would jump to the wrong agent. An id cannot do that: it
# either still exists, or it does not and we fall to the top.
#
# `top` is the first visible row, and it only ever moves far enough to keep the
# selection on screen.
export def keep-in-view [view: record, rows: list<record>, height: int]: nothing -> record {
    let n = $rows | length
    if $n == 0 { return ($view | merge {sel: "", top: 0}) }

    let ids = $rows | get id
    let sel = if (($view.sel? | default "") in $ids) { $view.sel } else { $ids | first }
    let at = $ids | enumerate | where item == $sel | get 0.index

    let h = [$height 1] | math max
    mut top = $view.top? | default 0
    if $top > ($n - $h) { $top = $n - $h }
    if $top < 0 { $top = 0 }
    if $at < $top { $top = $at }
    if $at >= ($top + $h) { $top = $at - $h + 1 }

    # An agent that went away takes the preview's scroll with it: the message
    # under the cursor is somebody else's now, and row 40 of it is not where you
    # were reading. The keys reset this when YOU move; this is the case where
    # the list moved instead.
    let stayed = $sel == ($view.sel? | default "")
    $view | merge {sel: $sel, top: $top, pv_top: (if $stayed { $view.pv_top? | default 0 } else { 0 })}
}

# Where the selection is in the list, and which row that is. Both answer
# "nothing" on an empty list rather than erroring, because an empty
# session-store is an ordinary state for a picker to be in.
export def index-of [rows: list<record>, view: record]: nothing -> int {
    let hit = $rows | enumerate | where {|e| $e.item.id == ($view.sel? | default "") } | get -o 0
    if ($hit == null) { -1 } else { $hit.index }
}

export def selected [rows: list<record>, view: record]: nothing -> any {
    let i = index-of $rows $view
    if $i < 0 { null } else { $rows | get $i }
}
