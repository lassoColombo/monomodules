# Terminal geometry and the graphics-protocol escape.
use std/assert
use std/testing *
use plot/render/term
use ./support.nu *

# ---- sizing ----

@test
def "the pane box always leaves a legible chart area" [] {
    # The actual pane size varies with how the tests are run, so assert the
    # invariants rather than the numbers: never wider than the pane, never so
    # small the chart is unreadable.
    let t = term size
    let box = term pane box
    assert greater or equal $box.cols 20
    assert greater or equal $box.rows 8
    if $t.columns > 0 {
        assert less or equal $box.cols $t.columns
        assert less or equal $box.rows $t.rows
    }
}

@test
def "PLOT_SIZE overrides the pane box" [] {
    let box = with-env {PLOT_SIZE: "120x40"} { term pane box }
    assert equal $box.cols 120
    assert equal $box.rows 40
}

@test
def "a malformed PLOT_SIZE is ignored rather than fatal" [] {
    let plain = term pane box
    let box = with-env {PLOT_SIZE: "nonsense"} { term pane box }
    assert equal $box $plain
}

@test
def "cell size falls back when the terminal will not answer" [] {
    let cell = isolated {|| term cell px }
    assert equal $cell.w 10
    assert equal $cell.h 21
}

@test
def "PLOT_CELL_PX overrides the measured cell size" [] {
    let cell = isolated {|| with-env {PLOT_CELL_PX: "20x53"} { term cell px } }
    assert equal $cell.w 20
    assert equal $cell.h 53
}

@test
def "plot pixels leave room for axes and title" [] {
    let px = term plot px {cols: 100, rows: 20} {w: 20, h: 53}
    # 100*20 = 2000 wide, 20*53 = 1060 tall, minus axis/title padding
    assert equal $px.width 1910
    assert equal $px.height 980
}

@test
def "a tiny pane still yields a legible minimum" [] {
    let px = term plot px {cols: 4, rows: 2} {w: 10, h: 20}
    assert equal $px.width 200
    assert equal $px.height 120
}

# ---- the escape sequence ----

@test
def "the show escape is a well-formed kitty graphics command" [] {
    let e = term escape /tmp/plot-fixture.png --cols 40 --rows 12 --id 7
    let esc = char --integer 27
    assert str contains $e $"($esc)_G"          # APC introducer
    assert str contains $e "a=T"                # transmit and display
    assert str contains $e "f=100"              # payload is PNG
    assert str contains $e "t=f"                # transmitted BY PATH, not inline
    assert str contains $e "i=7,c=40,r=12"
    assert str contains $e $"($esc)(char --integer 92)"   # ST terminator
}

@test
def "the escape carries the path, not the image bytes" [] {
    # This is the whole point of t=f: a chart of any size is ~50 bytes on the wire.
    let e = term escape /tmp/plot-fixture.png --cols 40 --rows 12
    let payload = $e | split row ";" | last | str replace -a (char --integer 27) "" | str replace -a (char --integer 92) ""
    assert equal ($payload | decode base64 | decode) "/tmp/plot-fixture.png"
    assert less ($e | str length) 120
}

@test
def "the delete escape targets one image id" [] {
    let e = term delete escape --id 3
    assert str contains $e "a=d"
    assert str contains $e "d=i"
    assert str contains $e "i=3"
}
