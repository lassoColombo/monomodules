# Where a chart ends up.
#
# Three destinations, decided by the flags a chart command was given:
#   --spec      -> return the Vega-Lite spec, render nothing
#   --out FILE  -> write the file (and never open it)
#   otherwise   -> draw it inline in this terminal
#
# The inline path is the default: this module exists so that "plot to terminal"
# needs no flag at all.

use ./vega.nu
use ./term
use ../lib/state.nu

# `parts` comes from a chart command, `look` carries the common flags.
export def main [parts: record, look: record]: nothing -> any {
    if $look.spec { return (vega spec $parts ($look | pixels-for-file)) }

    if (($look.out? | default null) != null) {
        let out = $look.out | path expand
        vega out ext $out | ignore              # validate the extension before rendering
        return (vega to image (vega spec $parts ($look | pixels-for-file)) $out 2.0)
    }

    draw-inline $parts $look
}

# File output honours --width/--height (pixels).
def pixels-for-file []: record -> record {
    let look = $in
    $look | merge {width: $look.width, height: $look.height}
}

# Inline: size the chart to the pane, render at native resolution, hand the PNG
# to the terminal by path. Returns nothing so the REPL prints no residue.
def draw-inline [parts: record, look: record]: nothing -> nothing {
    if not $nu.is-interactive {
        error make {msg: "plot: not an interactive terminal — use --out <file> to write an image, or --spec for the Vega-Lite spec"}
    }

    let box = term pane box
    let cell = term cell px
    let px = term plot px $box $cell

    let dir = scratch-dir
    prune $dir
    let png = mktemp -p $dir "plot-XXXXXXXX" --suffix ".png"

    vega to image (vega spec $parts ($look | merge {width: $px.width, height: $px.height})) $png 1.0 | ignore
    term show $png --cols $box.cols --rows $box.rows
}

# Rendered PNGs live under plot's own state dir rather than $TMPDIR, so they are
# ours to find and prune.
def scratch-dir []: nothing -> path {
    let d = state dir | path join "render"
    if not ($d | path exists) { mkdir $d }
    $d
}

# The terminal reads each PNG the moment it is sent and keeps its own copy of the
# pixels, so a rendered file is dead weight seconds later. Sweep the previous
# renders every time we make a new one; the window is generous purely to avoid
# racing a terminal that reads the file lazily.
def prune [dir: path]: nothing -> nothing {
    do -i {
        ls $dir
        | where type == file and modified < ((date now) - 2min)
        | each {|f| rm --force $f.name }
        | ignore
    }
}
