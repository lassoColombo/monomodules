# Store I/O, measured in-process against v1's real store module — so these are
# the costs v2 has to beat or keep, not the costs of a toy reimplementation.
#
# Run as its own script (rather than inside the harness shell) so XDG_DATA_HOME
# can be moved around freely without disturbing anything else.

use harness.nu *
use ../../ai/agent-notify/lib/store.nu

const ROOT = ($nu.temp-dir | path join "agent-notify2-bench-store")

# A record the shape v1 writes, with a preview of realistic weight: the bar shows
# ~750 characters, so that is about what a stored preview carries — twice, since
# the store holds a plain and a markdown copy.
def fake-rec [i: int] {
    let msg = 1..12 | each {|l| $"line ($l) of a realistic assistant message, long enough to matter." } | str join "\n"
    { session: "bench", pane_id: $i, tab_id: ($i mod 4), tab_position: ($i mod 4)
      tab_name: $"tab-($i mod 4)", pane_name: $"pane-($i)", pane_locked: true
      agent: "Claude", transcript: "/tmp/bench.jsonl", state: "awaiting"
      preview: $msg, preview_md: $msg }
}

def seed [n: int] {
    let dir = [$ROOT $"n_($n)"] | path join
    if ($dir | path exists) { rm --recursive --force $dir }
    mkdir ([$dir "agent-notify"] | path join)
    $env.XDG_DATA_HOME = $dir
    1..$n | each {|i| store put (fake-rec $i) } | ignore
    {n: $n, dir: $dir}
}

export def main [] {
    let dirs = [1 5 20 50] | each {|n| seed $n }
    let one = $dirs | get 0
    let many = $dirs | last
    let rec1 = [$one.dir "agent-notify" "bench.1.json"] | path join

    $env.XDG_DATA_HOME = $one.dir
    let a = [
        (inproc "store get      (1 record)" {|| store get "bench" 1 })
        (inproc "open           (json by extension)" {|| open $rec1 })
        (inproc "open --raw | from json" {|| open --raw $rec1 | from json })
        (inproc "store put      (atomic: save + mv)" {|| store put (fake-rec 1) })
        (inproc "to json        (1 record)" {|| fake-rec 1 | to json })
    ]

    let b = $dirs | each {|d|
        $env.XDG_DATA_HOME = $d.dir
        inproc $"store list     \(($d.n) records\)" {|| store list }
    }

    $env.XDG_DATA_HOME = $many.dir
    let pat = [$many.dir "agent-notify" "*.json"] | path join
    let c = [
        (inproc "glob *.json    (50, no read)" {|| glob $pat })
        (inproc "ls *.json      (50, no read)" {|| ls ($pat | into glob) })
    ]

    print ($a ++ $b ++ $c | fmt | table --width 90)
}
