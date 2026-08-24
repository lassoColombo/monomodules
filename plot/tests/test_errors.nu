# Every way a plot command can refuse, and what it says when it does.
# Bad input should name the flag or column at fault, never leak a nushell
# internal error.
use std/assert
use std/testing *
use plot
use ./support.nu *

@test
def "a missing x-axis names the flag" [] {
    let m = error message {|| isolated {|| sample wide | plot line --y [a] --spec } }
    assert str contains $m "--x-axis is required"
}

@test
def "a missing y names the flag" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --spec } }
    assert str contains $m "--y is required"
}

@test
def "an empty y list is rejected" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [] --spec } }
    assert str contains $m "--y is required"
}

@test
def "an unknown column lists what is available" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x nope --y [a] --spec } }
    assert str contains $m "column 'nope' not found"
    assert str contains $m "Available:"
}

@test
def "an unknown y column is caught" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [nope] --spec } }
    assert str contains $m "column 'nope' not found"
}

@test
def "a non-numeric y names the row and type" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [label] --spec } }
    assert str contains $m "must be numeric"
    assert str contains $m "row 0"
}

@test
def "an empty table is rejected" [] {
    let m = error message {|| isolated {|| [] | plot line -x x --y [a] --spec } }
    assert str contains $m "input table is empty"
}

@test
def "a list of non-records is rejected" [] {
    let m = error message {|| isolated {|| [1 2 3] | plot line -x x --y [a] --spec } }
    assert str contains $m "expected list<record>"
}

@test
def "an unknown bar style lists the valid ones" [] {
    let m = error message {|| isolated {|| sample cat | plot bar -x fruit --y [q1] --style nope --spec } }
    assert str contains $m "unknown --style 'nope'"
    assert str contains $m "clustered, stacked, normalized"
}

@test
def "an unknown step placement lists the valid ones" [] {
    let m = error message {|| isolated {|| sample wide | plot step -x x --y [a] --where nope --spec } }
    assert str contains $m "unknown --where 'nope'"
    assert str contains $m "pre, post, mid"
}

@test
def "an out path without an extension is rejected" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [a] --out /tmp/plot-noext } }
    assert str contains $m "has no extension"
}

@test
def "an unsupported out extension lists the supported ones" [] {
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [a] --out /tmp/plot-bad.xyz } }
    assert str contains $m "unsupported output extension 'xyz'"
    assert str contains $m "png"
}

@test
def "histogram requires a column" [] {
    let m = error message {|| isolated {|| sample wide | plot histogram --spec } }
    assert str contains $m "--col is required"
}

@test
def "histogram rejects a non-numeric column" [] {
    let m = error message {|| isolated {|| sample wide | plot histogram --col label --spec } }
    assert str contains $m "must be numeric"
}

@test
def "series mode accepts exactly one y column" [] {
    let m = error message {|| isolated {|| sample long | plot line -x t --series sensor --y [v t] --spec } }
    assert str contains $m "single --y column"
}

@test
def "an unknown series column is caught" [] {
    let m = error message {|| isolated {|| sample long | plot line -x t --series nope --y [v] --spec } }
    assert str contains $m "column 'nope' not found"
}

@test
def "drawing inline without a terminal explains the alternatives" [] {
    # Tests are not interactive, so the inline path must refuse with guidance
    # rather than emitting escape codes into a pipe.
    let m = error message {|| isolated {|| sample wide | plot line -x x --y [a] } }
    assert str contains $m "not an interactive terminal"
    assert str contains $m "--out"
    assert str contains $m "--spec"
}
