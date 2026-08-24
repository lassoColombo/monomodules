# File output. This is the only suite that actually runs vl-convert, so it is
# the slowest — everything else asserts on specs instead.
use std/assert
use std/testing *
use plot
use ./support.nu *

@before-each
def setup []: nothing -> record {
    {temp: (mktemp --tmpdir --directory)}
}

@after-each
def teardown [] {
    rm --recursive --force $in.temp
}

@test
def "png output is a real png" [] {
    let f = $in.temp | path join "chart.png"
    isolated {|| sample wide | plot line -x x --y [a] --out $f } | ignore
    assert ($f | path exists)
    assert equal (open --raw $f | bytes at 1..3 | decode) "PNG"
}

@test
def "svg output is a real svg" [] {
    let f = $in.temp | path join "chart.svg"
    isolated {|| sample wide | plot line -x x --y [a] --out $f } | ignore
    assert str contains (open --raw $f | decode) "<svg"
}

@test
def "pdf output is a real pdf" [] {
    let f = $in.temp | path join "chart.pdf"
    isolated {|| sample wide | plot line -x x --y [a] --out $f } | ignore
    assert equal (open --raw $f | bytes at 0..3 | decode) "%PDF"
}

@test
def "the output path is returned" [] {
    let f = $in.temp | path join "chart.png"
    let got = isolated {|| sample wide | plot line -x x --y [a] --out $f }
    assert equal $got $f
}

@test
def "an existing file is overwritten" [] {
    let f = $in.temp | path join "chart.png"
    "stale" | save -f $f
    isolated {|| sample wide | plot line -x x --y [a] --out $f } | ignore
    assert equal (open --raw $f | bytes at 1..3 | decode) "PNG"
}

@test
def "every chart command can render" [] {
    let d = $in.temp
    isolated {||
        sample wide | plot line     -x x --y [a b]        --out ($d | path join "line.png")     | ignore
        sample wide | plot scatter  -x x --y [a]          --out ($d | path join "scatter.png")  | ignore
        sample cat  | plot bar      -x fruit --y [q1 q2]  --out ($d | path join "bar.png")      | ignore
        sample nums | plot histogram --col v              --out ($d | path join "hist.png")     | ignore
        sample wide | plot step     -x x --y [a]          --out ($d | path join "step.png")     | ignore
        sample wide | plot impulses -x x --y [b]          --out ($d | path join "imp.png")      | ignore
        sample long | plot line -x t --series sensor --y [v] --out ($d | path join "long.png")  | ignore
    }
    let pngs = ls $d | where name =~ '\.png$'
    assert equal ($pngs | length) 7
    # A blank or truncated render would be far smaller than this.
    assert equal ($pngs | where size < 5kb | length) 0
}

@test
def "the size flags change the rendered image" [] {
    let small = $in.temp | path join "small.png"
    let large = $in.temp | path join "large.png"
    isolated {||
        sample wide | plot line -x x --y [a] --width 400 --height 300 --out $small | ignore
        sample wide | plot line -x x --y [a] --width 1400 --height 900 --out $large | ignore
    }
    assert greater (ls $large | get 0.size) (ls $small | get 0.size)
}

@test
def "PLOT_DEBUG dumps the spec that was rendered" [] {
    let f = $in.temp | path join "chart.png"
    let dump = $in.temp | path join "spec.json"
    isolated {|| with-env {PLOT_DEBUG: $dump} { sample wide | plot line -x x --y [a] --out $f } } | ignore
    assert ($dump | path exists)
    let spec = open $dump
    assert equal $spec.mark "line"
}
