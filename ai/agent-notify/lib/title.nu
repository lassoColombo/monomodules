# Pure string logic for agent titles — no I/O. Shared by mod.nu (which writes
# titles) and sketchybar.nu (which reads them), so the parse/format rules live
# in exactly one place.
#
#   Pane title: "<sym> <base>"    (one agent per pane — bare, no provider name)
#   Tab title:  "<syms> <base>"   (bare aggregate over the tab)

use const.nu *

# Split a title into {agent, symbol, base}. Reads the bare "<syms> <base>" form
# (symbol = the first marker) and still tolerates the legacy pane form
# "(<agent> <sym>) - <base>"; untagged titles (plain shells, Claude Code's own
# title) yield empty agent/symbol + clean base.
export def parse-title [name: string] {
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
    # Bare "<symbols> <base>": drop a leading run of marker tokens ("●", "●2"),
    # remembering the first as this title's symbol.
    let toks = $s | split row ' '
    mut i = 0
    mut sym = ""
    while $i < ($toks | length) {
        let t = $toks | get $i
        let hit = $markers | where {|m|
            ($t == $m) or (($t | str starts-with $m) and (($t | str substring ($m | str length)..) =~ '^[0-9]+$'))
        }
        if ($hit | is-empty) { break }
        if ($sym | is-empty) { $sym = ($hit | first) }
        $i += 1
    }
    {agent: "", symbol: $sym, base: ($toks | skip $i | str join " " | str trim)}
}

# Bare title: join a symbol string ("○", or a tab aggregate "▲ ●2") with a base.
# Either part may be empty; a fully empty title becomes " " (zellij needs non-empty).
export def bare-title [syms: string, base: string] {
    let t = [$syms $base] | where {|x| not ($x | is-empty) } | str join " "
    if ($t | is-empty) { " " } else { $t }
}

# Fold a list of per-pane symbols into a bare tab aggregate: "▲ ●2" (count > 1
# is suffixed). Empty in → empty out. Ordered by marker priority.
export def fold-symbols [syms: list<string>] {
    let present = $syms | where {|s| $s != "" }
    if ($present | is-empty) { return "" }
    $markers
        | each {|m| {sym: $m, n: ($present | where {|s| $s == $m} | length)} }
        | where n > 0
        | each {|c| if $c.n > 1 { $"($c.sym)($c.n)" } else { $c.sym } }
        | str join " "
}
