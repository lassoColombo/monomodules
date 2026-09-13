# Case group 2 — THE PARSE BUDGET: how many bytes of nushell the hot path may
# contain before the parse shows up next to the ~13ms process floor, and whether
# the entry point should be a script or a module import.
#
# The floor group showed a leaf import is nearly free (+0.04ms for 26 lines,
# +0.82ms for 108), which suggests a slope of a few µs per line. `hot.nu` will
# be a few hundred lines, so the slope — not the intercept — is what sets its
# size budget. Synthetic modules of known size measure it directly, rather than
# extrapolating from three real files whose contents differ in kind.

use harness.nu *

const REPO = path self ../..
const DIR = ($nu.temp-dir | path join "agent-notify-bench-synth")

# A function of roughly the shape agent-notify's code has: params, a couple of
# lets, a conditional, some string work. Not a comment farm and not a one-liner
# — comments are cheap to lex and would flatter the slope.
def one-func [i: int] {
    [ $"export def f($i) [name: string, n: int] {"
      "    let base = $name | str trim | str downcase"
      "    let tag = if ($n > 0) { $\"($base)-($n)\" } else { $base }"
      "    if ($tag | str starts-with \"x\") { $tag | str substring 1.. } else { $tag }"
      "}" ] | str join "\n"
}

def gen [nfuncs: int] {
    let path = [$DIR $"synth_($nfuncs).nu"] | path join
    1..$nfuncs | each {|i| one-func $i } | str join "\n\n" | save --force $path
    {n: $nfuncs, path: $path, bytes: (ls $path | get 0.size)}
}

export def slope [] {
    if not ($DIR | path exists) { mkdir $DIR }
    let files = [5 20 50 100 200 400] | each {|n| gen $n }
    print ($files | each {|f|
        span $"($f.n) funcs / ($f.bytes)" $"use ($f.path)" --rounds 12
    } | fmt | table)
    print ""
    print "bytes per case (for the slope):"
    print ($files | select n bytes | table)
}

# Do COMMENTS cost parse time? 31% of agent-notify's lines are prose, and this
# repo's whole style rests on that, so it matters whether the hot path can be
# documented like everything else or has to be terse with its explanation exiled
# to a cold sibling file. Three files of the same size, differing only in how
# much of them is comment.
export def comments [] {
    if not ($DIR | path exists) { mkdir $DIR }
    let code = gen 100                      # ~23kB of pure code
    let target = ($code.bytes | into int)

    let cline = "# a comment line of roughly the width this repo actually writes."
    let pure = [$DIR "pure_comments.nu"] | path join
    (1..(($target / (($cline | str length) + 1)) | into int) | each {|| $cline } | str join "\n")
        | save --force $pure

    # Half and half, interleaved the way real code is: a paragraph, then a func.
    let mixed = [$DIR "mixed.nu"] | path join
    (1..50 | each {|i| ([$cline $cline $cline (one-func $i)] | str join "\n") } | str join "\n\n")
        | save --force $mixed

    print ([
        (span "(nothing)" "")
        (span $"pure code     ($code.bytes)" $"use ($code.path)")
        (span $"pure comments ((ls $pure | get 0.size))" $"use ($pure)")
        (span $"half and half ((ls $mixed | get 0.size))" $"use ($mixed)")
    ] | fmt | table)
}

# Is `use` machinery itself costing anything a plain script would not, and is a
# script file cheaper than the same source handed to `-c`? Both matter: the hook
# entry point is ours to choose, and settings.json can just as easily name a
# script as a `-c` string.
export def entry [] {
    if not ($DIR | path exists) { mkdir $DIR }
    "" | save --force ([$DIR "empty.nu"] | path join)
    # 100 funcs, once as a module to `use` and once as a script to run directly.
    let mod = gen 100
    let script = [$DIR "as_script.nu"] | path join
    (open --raw $mod.path) + "\nf1 \"x\" 1 | ignore\n" | save --force $script

    print ([
        (wall "nu -c ''" [$NU "-n" "--no-std-lib" "-c" ""])
        (wall "nu empty.nu            (empty script file)" [$NU "-n" "--no-std-lib" ([$DIR "empty.nu"] | path join)])
        (wall "nu -c 'use synth_100'  (module import)" [$NU "-n" "--no-std-lib" "-c" $"use ($mod.path)"])
        (wall "nu as_script.nu        (same source, as script)" [$NU "-n" "--no-std-lib" $script])
    ] | fmt | table)
}
