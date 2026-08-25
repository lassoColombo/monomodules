# Drawing a rendered chart inside the terminal, with the kitty graphics protocol.
#
# This is what replaced "write a file and hand it to `start`". The PNG is
# transmitted BY PATH (t=f) rather than base64-chunked into the escape sequence,
# which turns a ~300KB write into ~120 bytes. The terminal decodes the file
# immediately and keeps its own copy of the pixels, so images survive scrollback
# and resize on their own.
#
# Requires a terminal that speaks the protocol: Ghostty, kitty, or zellij 0.45+
# running on top of one.

# Sane default if the terminal will not say: roughly a 10pt monospace cell.
const FALLBACK_CELL = {w: 10, h: 21}

# Cell size in pixels, so a chart is rendered at the resolution it will actually
# be displayed at AND with the same aspect ratio as its cell box (otherwise the
# terminal stretches it). Queried once and cached — the query briefly puts the
# tty in raw mode, so it must not run on every plot.
export def "cell px" []: nothing -> record {
    let override = $env.PLOT_CELL_PX? | default ""
    if ($override | is-not-empty) { return (parse-wh $override) }

    let cache = $nu.temp-dir | path join "plot-cell-px.nuon"
    if ($cache | path exists) {
        let c = try { open --raw $cache | from nuon } catch { null }
        if $c != null { return $c }
    }

    let measured = query-cell
    if $measured == null { return $FALLBACK_CELL }
    $measured | to nuon | save -f $cache
    $measured
}

# "20x53" -> {w: 20, h: 53}
def parse-wh [s: string]: nothing -> record {
    let p = $s | split row "x"
    if ($p | length) != 2 { return $FALLBACK_CELL }
    try { {w: ($p.0 | into int), h: ($p.1 | into int)} } catch { $FALLBACK_CELL }
}

# Ask the terminal: ESC[16t -> ESC[6;<height>;<width>t
#
# Shelled to bash because this needs a raw-mode tty read, which nushell has no
# native primitive for. Note macOS ships bash 3.2, whose `read -t` rejects
# fractional timeouts — hence the stty min/time form.
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

# How much of the pane a chart should occupy, in cells: nearly the full width,
# a bit over half the height, so the command and its output stay visible above.
# Override with $env.PLOT_SIZE = "100x24".
export def "pane box" []: nothing -> record {
    let override = $env.PLOT_SIZE? | default ""
    if ($override | is-not-empty) {
        let p = $override | split row "x"
        if ($p | length) == 2 {
            let parsed = try { {cols: ($p.0 | into int), rows: ($p.1 | into int)} } catch { null }
            if $parsed != null { return $parsed }
        }
    }

    let t = term size
    # term size reports 0x0 when there is no tty (piped, scripted).
    let cols = if $t.columns > 0 { $t.columns } else { 100 }
    let rows = if $t.rows > 0 { $t.rows } else { 30 }
    let want = [($rows * 0.6 | math floor), 8] | math max
    {
        cols: ([($cols - 2), 20] | math max)
        rows: ([$want, ($rows - 2)] | math min)
    }
}

# Pixel size to render at. Vega's width/height are the PLOTTING AREA, so leave
# room for the axes and title.
export def "plot px" [box: record, cell: record]: nothing -> record {
    {
        width:  ([(($box.cols * $cell.w) - 90), 200] | math max)
        height: ([(($box.rows * $cell.h) - 80), 120] | math max)
    }
}

# Draw a PNG at the cursor, scaled into a cols x rows cell box.
#
# Every chart gets a FRESH image id. Reusing an id is NOT replace-in-place: the
# terminal destroys the image it already holds under that id and draws the new
# one at the cursor — so a fixed id wipes the previous chart out of the
# scrollback each time another is drawn. Pass `--id` only to deliberately
# replace a specific image (an in-place refresh, which also needs the cursor
# parked back over it).
export def show [png: path, --cols: int, --rows: int, --id: int]: nothing -> nothing {
    let esc = char --integer 27
    let backslash = char --integer 92
    let payload = $png | path expand | encode base64
    let image_id = $id | default (next-id)

    print -n $"($esc)_Ga=T,f=100,t=f,i=($image_id),c=($cols),r=($rows),q=2;($payload)($esc)($backslash)"
    print ""
}

# A distinct image id per chart, kept inside the protocol's 32-bit range (and
# away from 0, which is not a valid id). Millisecond resolution is plenty: two
# charts drawn in the same millisecond could not be told apart on screen anyway.
def next-id []: nothing -> int {
    (((date now | into int) // 1_000_000) mod 4_000_000_000) + 1
}
