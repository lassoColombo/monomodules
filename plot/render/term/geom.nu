# How much of the pane an inline chart should occupy, in character cells.
#
# Width: nearly the full pane. Height: a bit over half, so the chart is large but
# still leaves the command and its result visible above the prompt.

# {cols, rows} in cells. Override with $env.PLOT_SIZE = "100x24".
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

    let want_rows = [($rows * 0.6 | math floor), 8] | math max
    {
        cols: ([($cols - 2), 20] | math max)
        rows: ([$want_rows, ($rows - 2)] | math min)
    }
}

# Pixel size to render at, so the image is native resolution in that cell box.
# Vega's width/height are the PLOTTING AREA, so subtract room for axes + title.
export def "plot px" [box: record, cell: record]: nothing -> record {
    let full_w = $box.cols * $cell.w
    let full_h = $box.rows * $cell.h
    {
        width:  ([($full_w - 90), 200] | math max)
        height: ([($full_h - 80), 120] | math max)
    }
}
