# Vega-Lite spec assembly and rasterisation via the `vl-convert` CLI
# (a self-contained Rust binary: https://github.com/vega/vl-convert).
#
# This file knows how to turn the pieces a chart command produces into a full
# Vega-Lite spec, and how to run that spec through vl-convert. It does NOT decide
# where the result goes — that is render/mod.nu.
#
# `parts` (from a chart command):
#   {data, mark, transform, encoding, x_channel, y_channel}
# `look` (the common presentation flags):
#   {title, xlabel, ylabel, xrange, yrange, width, height, grid,
#    legend, legend_pos, logx, logy, xformat, yformat}

use ../lib/theme

export def "out formats" []: nothing -> list<string> { ["png" "jpg" "jpeg" "svg" "pdf" "html"] }

def subcommand [ext: string]: nothing -> string {
    match $ext {
        "png" => "vl2png"
        "jpg" | "jpeg" => "vl2jpeg"
        "svg" => "vl2svg"
        "pdf" => "vl2pdf"
        "html" => "vl2html"
        _ => { error make {msg: $"plot: no vl-convert subcommand for '($ext)'"} }
    }
}

# Validate an --out path and return its extension.
export def "out ext" [out: path]: nothing -> string {
    let e = $out | path parse | get extension | str lowercase
    if ($e | is-empty) {
        error make {msg: $"plot: --out '($out)' has no extension; use one of: (out formats | str join ', ')"}
    }
    if ($e not-in (out formats)) {
        error make {msg: $"plot: unsupported output extension '($e)'; use one of: (out formats | str join ', ')"}
    }
    $e
}

# Assemble the full Vega-Lite spec.
export def spec [parts: record, look: record]: nothing -> record {
    let enc = layer-look $parts.encoding ($parts.x_channel? | default null) ($parts.y_channel? | default null) $look

    mut vl = {
        "$schema": "https://vega.github.io/schema/vega-lite/v5.json"
        width: $look.width
        height: $look.height
        data: {values: $parts.data}
        mark: $parts.mark
        encoding: $enc
        config: (theme vega-config)
    }
    if (($look.title? | default null) != null) { $vl = ($vl | insert title $look.title) }
    let tf = $parts.transform? | default []
    if ($tf | is-not-empty) { $vl = ($vl | insert transform $tf) }
    $vl
}

# Run a spec through vl-convert into a file. Returns the path.
export def "to image" [vl: record, out: path, scale: float]: nothing -> path {
    if (which vl-convert | is-empty) {
        error make {msg: "plot: `vl-convert` not found on PATH — install from https://github.com/vega/vl-convert/releases (or `cargo install vl-convert`)"}
    }
    let ext = out ext $out

    if ($env.PLOT_DEBUG? | default "" | is-not-empty) { $vl | to json | save -f $env.PLOT_DEBUG }

    let spec_file = mktemp --suffix ".vl.json"
    $vl | to json -r | save -f $spec_file

    # Vector formats ignore scale.
    let scale_args = if ($ext in ["png" "jpg" "jpeg"]) { ["--scale" ($scale | into string)] } else { [] }
    let result = ^vl-convert (subcommand $ext) --input $spec_file --output $out ...$scale_args | complete
    rm --force $spec_file

    if ($result.exit_code != 0) or (not ($out | path exists)) {
        error make {msg: $"plot: render failed\n($result.stderr | str trim)\n($result.stdout | str trim)"}
    }
    $out
}

# ---- presentation flags -> encoding ----

# Inject axis/scale into the x/y channels and legend into the color channel.
# Chart commands only set {field, type, ...}; everything driven by the common
# flags is centralised here.
def layer-look [encoding: record, x_channel: any, y_channel: any, look: record]: nothing -> record {
    mut enc = $encoding
    let cols = $enc | columns

    if ($x_channel != null) and ($x_channel in $cols) {
        let ch = $enc | get $x_channel
        let ty = $ch.type? | default ""
        $enc = ($enc | update $x_channel (merge-channel $ch
            (axis-of ($look.xlabel? | default null) $look.grid ($look.xformat? | default null) $ty)
            (scale-of $look.logx ($look.xrange? | default null) $ty)))
    }
    if ($y_channel != null) and ($y_channel in $cols) {
        let ch = $enc | get $y_channel
        let ty = $ch.type? | default ""
        $enc = ($enc | update $y_channel (merge-channel $ch
            (axis-of ($look.ylabel? | default null) $look.grid ($look.yformat? | default null) $ty)
            (scale-of $look.logy ($look.yrange? | default null) $ty)))
    }
    if ("color" in $cols) {
        let legend = if (not $look.legend) {
            null
        } else if (($look.legend_pos? | default null) != null) {
            {orient: $look.legend_pos}
        } else { {} }
        $enc = ($enc | update color (apply-legend ($enc | get color) $legend))
    }
    $enc
}

def axis-of [title: any, grid: bool, format: any, type: string]: nothing -> record {
    mut ax = {grid: $grid}
    if ($title != null) { $ax = ($ax | insert title $title) }
    if ($format != null) { $ax = ($ax | insert format $format) }
    if ($type == "nominal") { $ax = ($ax | insert labelAngle (-30)) }
    $ax
}

def scale-of [log: bool, range: any, type: string]: nothing -> record {
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

# null -> hide legend; {} -> default placement; {orient} -> positioned.
def apply-legend [ch: record, legend: any]: nothing -> record {
    if ($legend == null) {
        $ch | merge {legend: null}
    } else if ($legend | is-empty) {
        $ch
    } else {
        $ch | merge {legend: $legend}
    }
}
