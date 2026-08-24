# Pure string logic for agent titles — no I/O. Used to PROJECT store state onto
# zellij pane/tab titles, and to recover a pane's base name from its title.
#
#   Pane title: "<glyph> <base>"   (one agent per pane)
#   Tab title:  "<glyphs> <base>"  (aggregate over the tab)

use state.nu *

# Recover a title's base name: drop a leading run of marker tokens ("▴", "•2")
# and return the rest. Untagged titles (plain shells) come back unchanged. State
# is never read back FROM titles (the store holds it) — this only strips glyphs.
export def parse-title [name: string] {
    $name | str trim | split row ' '
    | skip while {|t|
        $markers | any {|m| ($t == $m) or (($t | str starts-with $m) and (($t | str substring ($m | str length)..) =~ '^[0-9]+$')) }
      }
    | str join " " | str trim
}

# Bare title: join a glyph string ("◦", or a tab aggregate "▴ •2") with a base.
# Either part may be empty; both empty gives "" — the signal to DROP our name
# (see rename-pane/rename-tab), never a blank " " label written over a real one.
export def bare-title [syms: string, base: string] {
    [$syms $base] | where {|x| not ($x | is-empty) } | str join " "
}

# Fold a list of per-pane glyphs into a bare tab aggregate: "▴ •2" (count > 1
# suffixed). Empty in → empty out. Ordered by marker priority.
export def fold-symbols [syms: list<string>] {
    let present = $syms | where {|s| $s != "" }
    if ($present | is-empty) { return "" }
    $markers
        | each {|m| {sym: $m, n: ($present | where {|s| $s == $m} | length)} }
        | where n > 0
        | each {|c| if $c.n > 1 { $"($c.sym)($c.n)" } else { $c.sym } }
        | str join " "
}
