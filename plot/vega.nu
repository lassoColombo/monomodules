# Vega-Lite backend — gnuplot's replacement. Each `plot` data subcommand builds
# a Vega-Lite spec (a record) and hands it here; we render it to an image by
# shelling out to the native `vl-convert` CLI — a self-contained Rust binary
# (install from https://github.com/vega/vl-convert/releases or `cargo install
# vl-convert`). The rendered image is then drawn straight into the terminal with
# the kitty graphics protocol (see `term.nu`) — `--out` writes a file instead,
# and nothing is ever opened in an external viewer.
#
# This file is to Vega-Lite what the old `render.nu` was to gnuplot.
#
# Spec shape (built by mod.nu):
#   {
#     data: list<record>   # validated table, projected as needed
#     mark: any            # vega-lite mark (string or record); omit when `layers`
#                          # is given. May be a closure taking `appearance`.
#     layers: list         # optional; [{mark, encoding?}, ...] sharing the
#                          # top-level encoding/data/transform. May be a closure
#                          # taking `appearance` (for size-dependent geometry).
#     encoding: record     # vega-lite encoding; the x/y channels carry just
#                          # {field,type} (+ bin/stack/etc). axis/scale/legend
#                          # are layered on here from `appearance`.
#     transform: list      # optional vega-lite transforms (default [])
#     x_channel: string    # encoding channel to receive xlabel/grid/logx/xrange
#     y_channel: string    # encoding channel to receive ylabel/grid/logy/yrange
#     appearance: record   # common flags (built by `plot appearance`); inline
#                          # drawing also stamps in the final width/height and
#                          # `font_scale`, so closures can size text to the pane.
#     out: path            # null → draw in the terminal; else write this file
#   }

use ./theme.nu
use ./term.nu

# Output formats vl-convert can emit that we accept, keyed by file extension.
def vega-formats []: nothing -> list<string> { ["png" "jpg" "jpeg" "svg" "pdf" "html"] }

# Map an output extension to the matching vl-convert subcommand.
def vega-subcommand [ext: string]: nothing -> string {
    match $ext {
        "png" => "vl2png"
        "jpg" | "jpeg" => "vl2jpeg"
        "svg" => "vl2svg"
        "pdf" => "vl2pdf"
        "html" => "vl2html"
        _ => { error make {msg: $"plot: no vl-convert subcommand for '($ext)'"} }
    }
}

# Entry point: turn a spec into a chart. With no `out` it is drawn in this
# terminal; with one, it is written to that file and NOT opened.
export def main [spec: record]: nothing -> any {
    if (which vl-convert | is-empty) {
        error make {msg: "plot: `vl-convert` not found on PATH — install it from https://github.com/vega/vl-convert/releases (or `cargo install vl-convert`)"}
    }

    let out = $spec.out? | default null
    if ($out != null) {
        let out_path = $out | path expand
        let ext = vega-ext $out_path
        # Raster formats get a 2x scale factor for crispness; vector formats ignore it.
        return (run-vl (build-spec $spec) $out_path $ext 2.0)
    }

    draw-inline $spec
}

# Draw in the terminal. The chart is sized to the pane first, so vl-convert
# renders it at the resolution — and aspect ratio — it will actually be shown at
# rather than having the terminal stretch an 800x600 image to fit.
def draw-inline [spec: record]: nothing -> nothing {
    if not $nu.is-interactive {
        error make {msg: "plot: not an interactive terminal — use --out <file> to write an image instead"}
    }

    let box = term pane box
    let cell = term cell px
    let px = term plot px $box $cell
    # Text rides along in `appearance`: it is sized in the same device pixels the
    # chart is rendered at, so it has to be scaled from the cell too.
    let sized = $spec | update appearance ($spec.appearance | merge {
        width: $px.width
        height: $px.height
        font_scale: (theme font scale $cell)
    })

    prune-scratch
    let png = mktemp --tmpdir "plot-XXXXXXXX" --suffix ".png"
    run-vl (build-spec $sized) $png "png" 1.0 | ignore
    term show $png --cols $box.cols --rows $box.rows
}

# The terminal decodes each PNG the moment it arrives and keeps its own copy of
# the pixels, so a rendered file is dead weight seconds later. Sweep the previous
# ones on the way past; the window is generous only to avoid racing a terminal
# that reads the file lazily.
def prune-scratch []: nothing -> nothing {
    do -i {
        glob ($nu.temp-dir | path join "plot-*.png")
        | where {|f| (ls $f | get 0.modified) < ((date now) - 2min) }
        | each {|f| rm --force $f }
        | ignore
    }
}

# Run a spec through vl-convert into a file. Returns the path.
def run-vl [vl: record, out: path, ext: string, scale: float]: nothing -> path {
    if ($env.PLOT_DEBUG? | default "" | is-not-empty) {
        $vl | to json | save -f $env.PLOT_DEBUG
    }

    let spec_file = (mktemp --suffix ".vl.json")
    $vl | to json -r | save -f $spec_file

    let scale_args = if ($ext in ["png" "jpg" "jpeg"]) { ["--scale" ($scale | into string)] } else { [] }
    let result = (^vl-convert (vega-subcommand $ext) --input $spec_file --output $out ...$scale_args | complete)
    rm --force $spec_file

    if ($result.exit_code != 0) or (not ($out | path exists)) {
        error make {msg: $"plot: render failed\n($result.stderr | str trim)\n($result.stdout | str trim)"}
    }
    $out
}

# Resolve the output format from the --out extension.
def vega-ext [out: path]: nothing -> string {
    let e = $out | path parse | get extension | str lowercase
    if ($e | is-empty) {
        error make {msg: $"plot: --out '($out)' has no extension; use one of: (vega-formats | str join ', ')"}
    }
    if ($e not-in (vega-formats)) {
        error make {msg: $"plot: unsupported output extension '($e)'; use one of: (vega-formats | str join ', ')"}
    }
    $e
}

# Assemble the full Vega-Lite spec from the subcommand's pieces + appearance.
def build-spec [spec: record]: nothing -> record {
    # Resolve the text scale once, up front: the config below AND every closure
    # that sizes its own text read it off `appearance`.
    let a = $spec.appearance | merge {font_scale: (resolve-font-scale $spec.appearance)}
    let enc = layer-appearance $spec.encoding ($spec.x_channel? | default null) ($spec.y_channel? | default null) $a

    mut vl = {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json"
        width: $a.width
        height: $a.height
        data: { values: $spec.data }
        encoding: $enc
        config: (theme vega-config --font-scale $a.font_scale)
    }
    # A spec carries EITHER one `mark` or a list of `layers` (each {mark, encoding?})
    # that share the top-level encoding, data and transforms.
    let layers = eval-frag ($spec.layers? | default null) $a
    if ($layers != null) {
        $vl = ($vl | insert layer $layers)
    } else {
        $vl = ($vl | insert mark (eval-frag ($spec.mark? | default null) $a))
    }
    if (($a.title? | default null) != null) { $vl = ($vl | insert title $a.title) }
    let tf = $spec.transform? | default []
    if ($tf | is-not-empty) { $vl = ($vl | insert transform $tf) }
    $vl
}

# Text scale: measured from the terminal cell by `draw-inline`, 1.0 for a file.
# `$env.PLOT_FONT_SCALE` overrides both, for a setup where the cell-width
# heuristic guesses wrong or simply for taste.
def resolve-font-scale [a: record]: nothing -> float {
    let override = $env.PLOT_FONT_SCALE? | default ""
    if ($override | is-not-empty) {
        let v = try { $override | into float } catch { null }
        if ($v != null) and ($v > 0) { return $v }
    }
    $a.font_scale? | default 1.0
}

# Mark/layer fragments may be given as a CLOSURE taking the resolved appearance,
# for geometry that depends on the final pixel size (arc radii, offsets): inline
# drawing rewrites width/height after the subcommand has built its spec, so the
# subcommand cannot compute those itself. Anything else passes straight through.
def eval-frag [frag: any, a: record]: nothing -> any {
    if (($frag | describe) == "closure") { do $frag $a } else { $frag }
}

# Inject axis/scale (from appearance) into the x/y channels and legend into the
# color channel. The subcommand only sets {field,type,...}; everything driven by
# the common flags is centralized here.
def layer-appearance [encoding: record, x_channel: any, y_channel: any, a: record]: nothing -> record {
    mut enc = $encoding
    let cols = $enc | columns

    if ($x_channel != null) and ($x_channel in $cols) {
        let ch = $enc | get $x_channel
        let ty = $ch.type? | default ""
        let axis = build-axis ($a.xlabel? | default null) $a.grid ($a.xformat? | default null) $ty true
        let scale = build-scale $a.logx ($a.xrange? | default null) $ty
        $enc = ($enc | update $x_channel (merge-channel $ch $axis $scale))
    }
    if ($y_channel != null) and ($y_channel in $cols) {
        let ch = $enc | get $y_channel
        let ty = $ch.type? | default ""
        let axis = build-axis ($a.ylabel? | default null) $a.grid ($a.yformat? | default null) $ty false
        let scale = build-scale $a.logy ($a.yrange? | default null) $ty
        $enc = ($enc | update $y_channel (merge-channel $ch $axis $scale))
    }
    if ("color" in $cols) {
        let legend = if (not $a.legend) {
            null
        } else if (($a.legend_pos? | default null) != null) {
            {orient: $a.legend_pos}
        } else {
            {}
        }
        $enc = ($enc | update color (apply-legend ($enc | get color) $legend))
    }
    $enc
}

# `rotate` tilts crowded category labels — worth it along the x axis, never on
# the y axis, where the labels already sit one per row.
def build-axis [title: any, grid: bool, format: any, type: string, rotate: bool]: nothing -> record {
    mut ax = { grid: $grid }
    if ($title != null) { $ax = ($ax | insert title $title) }
    if ($format != null) { $ax = ($ax | insert format $format) }
    if $rotate and ($type == "nominal") { $ax = ($ax | insert labelAngle (-30)) }
    $ax
}

def build-scale [log: bool, range: any, type: string]: nothing -> record {
    mut sc = {}
    if $log and ($type == "quantitative") { $sc = ($sc | insert type "log") }
    if ($range != null) { $sc = ($sc | insert domain $range) }
    $sc
}

def merge-channel [ch: record, axis: record, scale: record]: nothing -> record {
    mut out = $ch
    if ($axis | is-not-empty) { $out = ($out | insert axis $axis) }
    if ($scale | is-not-empty) { $out = ($out | insert scale $scale) }
    $out
}

# null → hide legend; {} → default placement; {orient} → positioned.
def apply-legend [ch: record, legend: any]: nothing -> record {
    if ($legend == null) {
        $ch | merge {legend: null}
    } else if ($legend | is-empty) {
        $ch
    } else {
        # Merge, so a channel that already carries legend settings of its own
        # (a value format, say) keeps them alongside the placement.
        $ch | merge {legend: (($ch.legend? | default {}) | merge $legend)}
    }
}
