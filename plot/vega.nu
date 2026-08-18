# Vega-Lite backend — gnuplot's replacement. Each `plot` data subcommand builds
# a Vega-Lite spec (a record) and hands it here; we render it to an image by
# shelling out to the native `vl-convert` CLI — a self-contained Rust binary
# (install from https://github.com/vega/vl-convert/releases or `cargo install
# vl-convert`). Vega-Lite has no interactive window, so we always write a file
# and open it with `start`.
#
# This file is to Vega-Lite what the old `render.nu` was to gnuplot.
#
# Spec shape (built by mod.nu):
#   {
#     data: list<record>   # validated table, projected as needed
#     mark: any            # vega-lite mark (string or record)
#     encoding: record     # vega-lite encoding; the x/y channels carry just
#                          # {field,type} (+ bin/stack/etc). axis/scale/legend
#                          # are layered on here from `appearance`.
#     transform: list      # optional vega-lite transforms (default [])
#     x_channel: string    # encoding channel to receive xlabel/grid/logx/xrange
#     y_channel: string    # encoding channel to receive ylabel/grid/logy/yrange
#     appearance: record   # common flags (built by `plot appearance`)
#     out: path            # may be null → temp file
#     open: bool
#   }

use ./theme.nu

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

# Entry point: turn a spec into a rendered image file (opened unless told not to).
export def main [spec: record]: nothing -> any {
    if (which vl-convert | is-empty) {
        error make {msg: "plot: `vl-convert` not found on PATH — install it from https://github.com/vega/vl-convert/releases (or `cargo install vl-convert`)"}
    }

    let ext = vega-ext ($spec.out? | default null)
    let out_path = if (($spec.out? | default null) != null) {
        $spec.out | path expand
    } else {
        mktemp --suffix $".($ext)"
    }

    let vl = build-spec $spec
    if ($env.PLOT_DEBUG? | default "" | is-not-empty) {
        $vl | to json | save -f $env.PLOT_DEBUG
    }

    let spec_file = (mktemp --suffix ".vl.json")
    $vl | to json -r | save -f $spec_file

    # raster formats get a 2x scale factor for crispness; vector formats ignore it
    let scale_args = if ($ext in ["png" "jpg" "jpeg"]) { ["--scale" "2.0"] } else { [] }
    let result = (^vl-convert (vega-subcommand $ext) --input $spec_file --output $out_path ...$scale_args | complete)
    rm --force $spec_file

    if ($result.exit_code != 0) or (not ($out_path | path exists)) {
        error make {msg: $"plot: render failed\n($result.stderr | str trim)\n($result.stdout | str trim)"}
    }

    if ($spec.open? | default true) { start $out_path }
    $out_path
}

# Resolve the output format from the --out extension. With no --out (a temp file),
# default to PDF: it's vector (zooms losslessly) AND opens in a native viewer
# (macOS Preview) instead of the browser, which makes it the better "just show me"
# default. An explicit --out extension always wins (use `--out x.png` for a raster,
# `--out x.svg` for SVG).
def vega-ext [out: any]: nothing -> string {
    if ($out == null) { return "pdf" }
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
    let a = $spec.appearance
    let enc = layer-appearance $spec.encoding ($spec.x_channel? | default null) ($spec.y_channel? | default null) $a

    mut vl = {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json"
        width: $a.width
        height: $a.height
        data: { values: $spec.data }
        mark: $spec.mark
        encoding: $enc
        config: (theme vega-config)
    }
    if (($a.title? | default null) != null) { $vl = ($vl | insert title $a.title) }
    let tf = $spec.transform? | default []
    if ($tf | is-not-empty) { $vl = ($vl | insert transform $tf) }
    $vl
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
        let axis = build-axis ($a.xlabel? | default null) $a.grid ($a.xformat? | default null) $ty
        let scale = build-scale $a.logx ($a.xrange? | default null) $ty
        $enc = ($enc | update $x_channel (merge-channel $ch $axis $scale))
    }
    if ($y_channel != null) and ($y_channel in $cols) {
        let ch = $enc | get $y_channel
        let ty = $ch.type? | default ""
        let axis = build-axis ($a.ylabel? | default null) $a.grid ($a.yformat? | default null) $ty
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

def build-axis [title: any, grid: bool, format: any, type: string]: nothing -> record {
    mut ax = { grid: $grid }
    if ($title != null) { $ax = ($ax | insert title $title) }
    if ($format != null) { $ax = ($ax | insert format $format) }
    if ($type == "nominal") { $ax = ($ax | insert labelAngle (-30)) }
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
        $ch | merge {legend: $legend}
    }
}
