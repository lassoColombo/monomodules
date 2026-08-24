# Spec-building semantics. These never rasterise anything: --spec returns the
# Vega-Lite spec, so the whole suite runs without touching vl-convert.
use std/assert
use std/testing *
use plot
use ./support.nu *

# ---- marks ----

@test
def "line uses a line mark and folds wide input" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a b] --spec }
    assert equal $s.mark "line"
    assert equal $s.transform.0.fold ["a" "b"]
    assert equal $s.encoding.x.field "x"
    assert equal $s.encoding.y.field "value"
    assert equal $s.encoding.color.field "series"
}

@test
def "line smoothing becomes an interpolate" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --smooth monotone --spec }
    assert equal $s.mark.type "line"
    assert equal $s.mark.interpolate "monotone"
}

@test
def "line smooth none stays a plain mark" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --smooth none --spec }
    assert equal $s.mark "line"
}

@test
def "scatter uses a filled point mark" [] {
    let s = isolated {|| sample wide | plot scatter -x x --y [a] --shape diamond --point-size 2.0 --spec }
    assert equal $s.mark.type "point"
    assert equal $s.mark.shape "diamond"
    assert equal $s.mark.filled true
    assert equal $s.mark.size 80
}

@test
def "impulses draw rules anchored at zero" [] {
    let s = isolated {|| sample wide | plot impulses -x x --y [a] --linewidth 4.0 --spec }
    assert equal $s.mark.type "rule"
    assert equal $s.mark.size 4.0
    assert equal $s.encoding.y2.datum 0
}

@test
def "step maps where onto vega interpolate" [] {
    let pre  = isolated {|| sample wide | plot step -x x --y [a] --where pre --spec }
    let post = isolated {|| sample wide | plot step -x x --y [a] --where post --spec }
    let mid  = isolated {|| sample wide | plot step -x x --y [a] --where mid --spec }
    assert equal $pre.mark.interpolate "step-before"
    assert equal $post.mark.interpolate "step-after"
    assert equal $mid.mark.interpolate "step"
}

# ---- bar styles ----

@test
def "clustered bars offset by series and do not stack" [] {
    let s = isolated {|| sample cat | plot bar -x fruit --y [q1 q2] --spec }
    assert equal $s.encoding.y.stack null
    assert equal $s.encoding.xOffset.field "series"
    assert equal $s.encoding.x.type "nominal"
}

@test
def "stacked bars stack and drop the offset" [] {
    let s = isolated {|| sample cat | plot bar -x fruit --y [q1 q2] --style stacked --spec }
    assert equal $s.encoding.y.stack true
    assert equal ("xOffset" in ($s.encoding | columns)) false
}

@test
def "normalized bars stack to a share and default to percent ticks" [] {
    let s = isolated {|| sample cat | plot bar -x fruit --y [q1 q2] --style normalized --spec }
    assert equal $s.encoding.y.stack "normalize"
    assert equal $s.encoding.y.axis.format "%"
}

@test
def "an explicit yformat beats the normalized default" [] {
    let s = isolated {|| sample cat | plot bar -x fruit --y [q1 q2] --style normalized --yformat ".2f" --spec }
    assert equal $s.encoding.y.axis.format ".2f"
}

# ---- histogram ----

@test
def "histogram bins and counts" [] {
    let s = isolated {|| sample nums | plot histogram --col v --bins 20 --spec }
    assert equal $s.transform.0.bin.maxbins 20
    assert equal $s.encoding.y.field "__count"
    assert equal $s.encoding.x.bin "binned"
    assert equal $s.encoding.y.axis.title "count"
}

@test
def "normalized histogram computes a frequency" [] {
    let s = isolated {|| sample nums | plot histogram --col v --normalize --spec }
    assert equal $s.encoding.y.field "__freq"
    assert equal $s.encoding.y.axis.title "frequency"
    assert equal ($s.transform | length) 4
}

# ---- wide vs long input ----

@test
def "long input reads real columns and needs no fold" [] {
    let s = isolated {|| sample long | plot line -x t --series sensor --y [v] --spec }
    assert equal ("transform" in ($s | columns)) false
    assert equal $s.encoding.y.field "v"
    assert equal $s.encoding.color.field "sensor"
}

# ---- the legend heuristic ----

@test
def "a single series hides the legend" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --spec }
    assert equal $s.encoding.color.legend null
}

@test
def "two series leave the legend at its default" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a b] --spec }
    assert equal ("legend" in ($s.encoding.color | columns)) false
}

@test
def "no-legend hides it even with several series" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a b] --no-legend --spec }
    assert equal $s.encoding.color.legend null
}

@test
def "legend-pos sets the orientation" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a b] --legend-pos top-right --spec }
    assert equal $s.encoding.color.legend.orient "top-right"
}

# ---- axis type detection ----

@test
def "x column type drives the encoding type" [] {
    let num = isolated {|| sample wide | plot line -x x --y [a] --spec }
    let cat = isolated {|| sample cat | plot line -x fruit --y [q1] --spec }
    assert equal $num.encoding.x.type "quantitative"
    assert equal $cat.encoding.x.type "nominal"
}

# ---- presentation flags ----

@test
def "labels titles and grid land on the spec" [] {
    let s = isolated {||
        sample wide | plot line -x x --y [a] --title "T" --xlabel "X" --ylabel "Y" --grid --spec
    }
    assert equal $s.title "T"
    assert equal $s.encoding.x.axis.title "X"
    assert equal $s.encoding.y.axis.title "Y"
    assert equal $s.encoding.x.axis.grid true
}

@test
def "ylabel defaults to the column name for one series only" [] {
    let one  = isolated {|| sample wide | plot line -x x --y [a] --spec }
    let both = isolated {|| sample wide | plot line -x x --y [a b] --spec }
    assert equal $one.encoding.y.axis.title "a"
    assert equal ("title" in ($both.encoding.y.axis | columns)) false
}

@test
def "log flags become log scales" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --logx --logy --spec }
    assert equal $s.encoding.x.scale.type "log"
    assert equal $s.encoding.y.scale.type "log"
}

@test
def "ranges become scale domains" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --xrange [0 10] --yrange [1 100] --spec }
    assert equal $s.encoding.x.scale.domain [0 10]
    assert equal $s.encoding.y.scale.domain [1 100]
}

@test
def "d3 formats reach the axes" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --xformat ".2f" --yformat "$,.0f" --spec }
    assert equal $s.encoding.x.axis.format ".2f"
    assert equal $s.encoding.y.axis.format "$,.0f"
}

@test
def "log scale is ignored on a categorical axis" [] {
    let s = isolated {|| sample cat | plot bar -x fruit --y [q1] --logx --spec }
    assert equal ("scale" in ($s.encoding.x | columns)) false
}

# ---- theme and size ----

@test
def "the theme config is attached" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --spec }
    assert equal $s.config.background "#191724"
    assert equal ($s.config.range.category | length) 12
}

@test
def "width and height default for file output" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --spec }
    assert equal $s.width 800
    assert equal $s.height 600
}

@test
def "width and height are overridable" [] {
    let s = isolated {|| sample wide | plot line -x x --y [a] --width 1400 --height 400 --spec }
    assert equal $s.width 1400
    assert equal $s.height 400
}
