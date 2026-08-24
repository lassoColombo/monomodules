# The column memory that powers flag completion.
#
# A nushell completer cannot see pipeline input, so plot records the shape of the
# last table it drew and completes against that. These tests pin that contract.
use std/assert
use std/testing *
use plot
use plot/lib/state.nu
use plot/lib/complete.nu
use ./support.nu *

@test
def "recall is empty before anything has been plotted" [] {
    let cols = isolated {|| state recall columns "all" }
    assert equal $cols []
}

@test
def "plotting records the table columns" [] {
    let cols = isolated {||
        sample wide | plot line -x x --y [a] --spec | ignore
        state recall columns "all"
    }
    assert equal $cols ["x" "a" "b" "label"]
}

@test
def "columns are split by type for the right flags" [] {
    let r = isolated {||
        sample wide | plot line -x x --y [a] --spec | ignore
        {numeric: (state recall columns "numeric"), other: (state recall columns "other")}
    }
    # --y must be measurable; --series names the lines.
    assert equal $r.numeric ["x" "a" "b"]
    assert equal $r.other ["label"]
}

@test
def "completers surface the remembered columns" [] {
    let r = isolated {||
        sample wide | plot line -x x --y [a] --spec | ignore
        {all: (complete columns), num: (complete numeric-columns), lab: (complete label-columns)}
    }
    assert equal $r.all ["x" "a" "b" "label"]
    assert equal $r.num ["x" "a" "b"]
    assert equal $r.lab ["label"]
}

@test
def "the last plot wins" [] {
    let cols = isolated {||
        sample wide | plot line -x x --y [a] --spec | ignore
        sample cat  | plot bar -x fruit --y [q1] --spec | ignore
        state recall columns "all"
    }
    assert equal $cols ["fruit" "q1" "q2"]
}

@test
def "histogram records columns too" [] {
    let cols = isolated {||
        sample nums | plot histogram --col v --spec | ignore
        state recall columns "all"
    }
    assert equal $cols ["v"]
}

@test
def "state is keyed by session so panes do not collide" [] {
    let d = mktemp --tmpdir --directory
    let one = with-env {PLOT_STATE: $d, ZELLIJ_SESSION_NAME: "alpha"} {
        sample wide | plot line -x x --y [a] --spec | ignore
        state dir
    }
    let two = with-env {PLOT_STATE: $d, ZELLIJ_SESSION_NAME: "beta"} {
        state recall columns "all"
    }
    rm --recursive --force $d
    assert str contains $one "alpha"
    # beta has plotted nothing, so it must not see alpha's columns.
    assert equal $two []
}

@test
def "a corrupt cache degrades to no completions" [] {
    # Completion must never explode in the middle of typing a command.
    let cols = isolated {||
        "not valid nuon {{{" | save -f (state dir | path join "last-columns.nuon")
        state recall columns "all"
    }
    assert equal $cols []
}
