# What the terminal will tell us about itself.
#
# Only one thing is needed: the pixel size of a character cell, so a chart can be
# rendered at the resolution it will actually be displayed at. Queried once and
# cached — the query briefly puts the tty in raw mode, so it should not run on
# every plot.
#
# NOTE: do NOT use ESC[14t (text-area pixels) to derive pane geometry. Under
# zellij it reports the whole terminal window, not the pane. See
# .notes/phase0-findings.md.

use ../../lib/state.nu

# Sane default if the terminal will not say (roughly a 10pt monospace cell).
const FALLBACK = {w: 10, h: 21}

# Cell size in pixels: {w, h}.
export def "cell px" []: nothing -> record {
    let override = $env.PLOT_CELL_PX? | default ""
    if ($override | is-not-empty) { return (parse-wh $override) }

    let cache = state dir | path join "cell-px.nuon"
    if ($cache | path exists) {
        let c = try { open --raw $cache | from nuon } catch { null }
        if $c != null { return $c }
    }

    let q = query-cell
    if $q == null { return $FALLBACK }
    $q | to nuon | save -f $cache
    $q
}

# "20x53" -> {w: 20, h: 53}
def parse-wh [s: string]: nothing -> record {
    let p = $s | split row "x"
    if ($p | length) != 2 { return $FALLBACK }
    try { {w: ($p.0 | into int), h: ($p.1 | into int)} } catch { $FALLBACK }
}

# Ask the terminal: ESC[16t -> ESC[6;<height>;<width>t
# Shelled to bash because this needs raw-mode tty reads, which nushell has no
# native primitive for.
def query-cell []: nothing -> any {
    if not $nu.is-interactive { return null }
    let r = do -i {
        ^bash -c 'exec < /dev/tty; stty raw -echo min 0 time 10; printf "\033[16t" > /dev/tty; head -c 32; stty sane'
    } | complete
    if $r.exit_code != 0 { return null }
    let m = $r.stdout | parse -r '\[6;(?<h>\d+);(?<w>\d+)t'
    if ($m | is-empty) { return null }
    {w: ($m.0.w | into int), h: ($m.0.h | into int)}
}
