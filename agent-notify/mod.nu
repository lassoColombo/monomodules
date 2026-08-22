# Reflects AI-agent state in the zellij pane/tab titles and an on-disk store.
#
#  - Pane: "(<agent> <sym>) - <base>" for THIS pane's agent (agent name kept
#          here, since a pane is one agent).
#  - Tab:  a bare AGGREGATE over every agent pane in the tab — just the symbols,
#          no agent name, no parens: "▲ ●2 - <base>" -> "▲ ●2 <base>". Because
#          the tab name is a pure function of all panes' states, concurrent
#          agents sharing a tab converge instead of clobbering each other.
#
# Base names are recovered by stripping any leading tag first (both the pane's
# "(...) - base" form and the tab's bare "<symbols> base" form).
# Targets the pane the caller runs in via $ZELLIJ_PANE_ID. No-op outside zellij.
#
# Every state change is also persisted to an on-disk store (see lib/store.nu),
# which backs the cross-session notifier (SketchyBar) and the session switcher.

use lib/const.nu *
use lib/store.nu *
export use jump.nu *
export use sketchybar.nu *

const markers = [$S_NEED $S_WAIT $S_WORK]   # priority order: most urgent first

# Split a title into {agent, symbol, base}. Handles the pane form
# "(<agent> <sym>) - <base>" and the tab form "<syms> <base>"; untagged titles
# (plain shells, Claude Code's own title) yield empty agent/symbol + clean base.
def parse-title [name: string] {
    let s = $name | str trim
    let p = $s | parse --regex '^\((?<head>[^)]*)\)\s*-\s*(?<base>.*)$'
    if not ($p | is-empty) {
        let head = $p | get head.0
        return {
            agent: ($head | str trim | split row ' ' | get -o 0 | default "")
            symbol: ($markers | where {|m| $head | str contains $m} | get -o 0 | default "")
            base: ($p | get base.0 | str trim)
        }
    }
    # Bare "<symbols> <base>": drop a leading run of marker tokens ("●", "●2").
    let toks = $s | split row ' '
    mut i = 0
    while $i < ($toks | length) {
        let t = $toks | get $i
        let hit = $markers | where {|m|
            ($t == $m) or (($t | str starts-with $m) and (($t | str substring ($m | str length)..) =~ '^[0-9]+$'))
        }
        if ($hit | is-empty) { break }
        $i += 1
    }
    {agent: "", symbol: "", base: ($toks | skip $i | str join " " | str trim)}
}

def pane-of [panes: table, id: int] { $panes | where id == $id | get -o 0 }

def fmt-head [agent: string, symbol: string] {
    if ($symbol | is-empty) { $"\(($agent)\)" } else { $"\(($agent) ($symbol)\)" }
}

def join-name [head: string, base: string] {
    if ($head | is-empty) {
        if ($base | is-empty) { " " } else { $base }
    } else if ($base | is-empty) { $head } else { $"($head) - ($base)" }
}

# Bare symbol summary for a tab: fold every agent pane's marker into one string
# ("▲ ●2"), substituting my own (possibly not-yet-rendered) symbol for my pane.
def tab-symbols [panes: table, tab_id: int, my_pane: int, my_symbol: string] {
    let syms = $panes
        | where tab_id == $tab_id
        | each {|p| if $p.id == $my_pane { $my_symbol } else { (parse-title $p.title).symbol } }
        | where {|s| $s != "" }
    if ($syms | is-empty) { return "" }
    $markers
        | each {|m| {sym: $m, n: ($syms | where {|s| $s == $m} | length)} }
        | where n > 0
        | each {|c| if $c.n > 1 { $"($c.sym)($c.n)" } else { $c.sym } }
        | str join " "
}

# Map a state glyph to the store's state name.
def state-name [symbol: string] {
    if $symbol == $S_NEED { "needs-attention" } else if $symbol == $S_WAIT { "awaiting" } else if $symbol == $S_WORK { "working" } else { "idle" }
}

def my-pane-id [] {
    if ($env.ZELLIJ? | is-empty) { return null }
    let s = $env.ZELLIJ_PANE_ID? | default ""
    if ($s | is-empty) { return null }
    $s | into int
}

# Core: render this pane's marker, recompute the tab aggregate, and persist to
# the store. `name` overrides the pane base; `drop_prefix` removes this pane's
# tag entirely (for `clear`).
def render [agent: string, symbol: string, name?: any, drop_prefix = false] {
    let pane_id = my-pane-id
    if $pane_id == null { return }
    let panes = ^zellij action list-panes -t -j | from json
    let me = pane-of $panes $pane_id
    if $me == null { return }

    let cur = parse-title $me.title
    let pane_base = if ($name | is-empty) { $cur.base } else { $name }

    # Pane: "(agent sym) - base" (agent kept — a pane is a single agent).
    let pane_head = if $drop_prefix { "" } else { fmt-head $agent $symbol }
    ^zellij action rename-pane --pane-id ($pane_id | into string) (join-name $pane_head $pane_base)

    # Tab: bare "<symbols> <base>" aggregate — no agent, no parens.
    let tab_base = (parse-title $me.tab_name).base
    let my_sym = if $drop_prefix { "" } else { $symbol }
    let syms = tab-symbols $panes $me.tab_id $pane_id $my_sym
    let tab_name = [$syms $tab_base] | where {|x| not ($x | is-empty) } | str join " "
    ^zellij action rename-tab --tab-id $me.tab_id (if ($tab_name | is-empty) { " " } else { $tab_name })

    # Persist to the on-disk store (backs the cross-session notifier + switcher).
    let session = $env.ZELLIJ_SESSION_NAME? | default ""
    if ($session | is-not-empty) {
        if $drop_prefix {
            store-drop $session $pane_id
        } else {
            store-put {
                session: $session
                pane_id: $pane_id
                tab_position: ($me.tab_position? | default 0)
                tab_name: (parse-title $me.tab_name).base
                agent: $agent
                state: (state-name $symbol)
                base: $pane_base
                updated_at: (date now | format date "%+")
            }
        }
    }
}

# SessionStart: tag pane with "(<agent>)". Optional `name` sets the pane base.
export def session-start [agent: string, name?: string] {
    render $agent "" $name
}

# "(<agent> ▲)" — agent is blocked, needs user attention.
export def needs-attention [agent: string] { render $agent $S_NEED }

# "(<agent> ○)" — agent is actively working.
export def working [agent: string] { render $agent $S_WORK }

# "(<agent> ●)" — agent returned control, your turn.
export def awaiting [agent: string] { render $agent $S_WAIT }

# Remove this pane's tag; recompute the tab aggregate over the remaining agents.
export def clear [] { render "" "" null true }
