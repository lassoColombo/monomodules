# Measurement primitives for the agent-notify2 design spike.
#
# Three things need measuring and they need three different methods:
#
#   wall   per-spawn WALL time — what delays the agent's turn. Reported as a
#          distribution (p50/p95), because spawn latency is right-skewed and a
#          mean hides the tail that is actually felt.
#   cpu    per-spawn CPU time (user+sys, descendants included) — what pins the
#          machine when an event fires many times a second. macOS
#          `/usr/bin/time` prints 2 decimals, i.e. 10ms granularity, so a single
#          15ms process is UNMEASURABLE: the cost is amortised over `reps`
#          spawns inside one wrapper and the harness's own loop is subtracted.
#   span   nu's own attribution via `--log-level perf`, which separates
#          `evaluate_commands` (parse + eval of MY code — the only part a design
#          can influence) from the fixed process/runtime overhead.
#
# Every spawn measurement is warmed up: the first runs of a 40MB binary pay dyld
# and page-cache costs steady state does not (measured 11.2ms → 7.4ms over a
# dozen runs), and reporting those as the number would flatter nothing and
# mislead everything.
#
# The harness itself costs something: nu spawns `/usr/bin/true` in ~1.9ms, so
# that case is always measured too and is the floor every other spawn sits on.

export const NU = "/opt/homebrew/bin/nu"
const TIME = "/usr/bin/time"

# ── stats ─────────────────────────────────────────────────────────────────────

def pct [times: list<duration>, p: float] {
    let s = $times | sort
    let n = $s | length
    let i = [((($n - 1) * $p) | math round | into int) ($n - 1)] | math min
    $s | get $i
}

export def stats [label: string, times: list<duration>] {
    if ($times | is-empty) { return {case: $label, n: 0} }
    { case: $label
      n: ($times | length)
      min: ($times | math min)
      p50: (pct $times 0.5)
      p95: (pct $times 0.95) }
}

# Durations print as "13ms 452µs 167ns", which in a table of ten cases wraps into
# unreadable soup. Everything here is milliseconds, so say so once in the header
# and render plain numbers.
def msf [d: any] { if ($d == null) { null } else { ((($d / 1ms) * 100) | math round) / 100 } }

export def fmt [] {
    $in | each {|r| {
        case: $r.case
        n: ($r.n? | default 0)
        min_ms: (msf ($r.min?))
        p50_ms: (msf ($r.p50?))
        p95_ms: (msf ($r.p95?))
    }}
}

export def fmt-cpu [] {
    $in | each {|r| {
        case: $r.case
        reps: ($r.reps? | default 0)
        cpu_ms: (msf ($r.cpu_per?))
        wall_ms: (msf ($r.wall_per?))
        note: ($r.note? | default "")
    }}
}

# ── wall: per-spawn latency distribution ──────────────────────────────────────

# `--stdin` feeds the process a payload (a hook body, a markdown message). Only
# piped when asked: an inherited stdin and a closed pipe are not the same thing,
# and the cases measured without it should stay comparable.
export def wall [
    label: string
    cmd: list<string>
    --rounds: int = 40
    --warmup: int = 8
    --vars: record = {}
    --stdin: string
    --prepare: closure
] {
    let exe = $cmd | first
    let rest = $cmd | skip 1
    let run = if ($stdin == null) {
        {|| try { ^$exe ...$rest out+err> /dev/null } }
    } else {
        {|| try { $stdin | ^$exe ...$rest out+err> /dev/null } }
    }
    # `--prepare` runs OUTSIDE the timed window, before each round. Needed for any
    # command that is idempotent in effect: writing a record makes the next run
    # take the early-return path, so measuring "the first time" repeatedly means
    # undoing the write between rounds.
    let times = with-env $vars {
        for _ in 1..$warmup { if ($prepare != null) { do $prepare }; do $run }
        1..$rounds | each {
            if ($prepare != null) { do $prepare }
            timeit { do $run }
        }
    }
    stats $label $times
}

# ── cpu: amortised user+sys per spawn ─────────────────────────────────────────

# A nu program that spawns `cmd` `reps` times. Single-quoted so `$c` reaches the
# inner shell as source, not as this shell's value.
def loop-src [cmd: list<string>, reps: int] {
    let head = ('let c = ' + ($cmd | to nuon) + '; 1..' + ($reps | into string))
    if ($cmd | is-empty) {
        ($head + ' | each {|| } | ignore')
    } else {
        ($head + ' | each {|| run-external ($c | first) ...($c | skip 1) out+err> /dev/null } | ignore')
    }
}

# Wall + CPU of one `/usr/bin/time -l` run, in seconds. null if unparseable.
def time-l [src: string, envr: record] {
    let r = with-env $envr { ^$TIME -l $NU -n --no-std-lib -c $src | complete }
    let got = $r.stderr | lines
        | parse --regex '(?<real>[0-9.]+)\s+real\s+(?<user>[0-9.]+)\s+user\s+(?<sys>[0-9.]+)\s+sys'
        | get -o 0
    if ($got == null) { return null }
    { real: ($got.real | into float)
      cpu: (($got.user | into float) + ($got.sys | into float)) }
}

# Marginal CPU per invocation: the spawn loop's CPU minus the same loop spawning
# nothing, over `reps`. `reps` has to be large enough that the total clears the
# 10ms tick by a wide margin — 40 spawns of a ~20ms nu is ~0.8s, ~80 ticks.
#
# A failing command would abort nu's `each` on the first iteration and the
# subtraction would quietly come out near zero — which is how this read "0sec"
# for the cases whose module could not be found (NU_LIB_DIRS does not survive
# two hops: nu turns it into a list internally and exports that list stringified,
# so the grandchild gets nonsense. Pass `-I` instead of the env var). So the
# command is run once up front and a non-zero exit is reported, never averaged.
export def cpu [
    label: string
    cmd: list<string>
    --reps: int = 40
    --vars: record = {}
] {
    let check = with-env $vars { ^($cmd | first) ...($cmd | skip 1) | complete }
    if $check.exit_code != 0 {
        return {case: $label, reps: 0, note: $"FAILED exit ($check.exit_code)"}
    }
    let base = time-l (loop-src [] $reps) $vars
    let run = time-l (loop-src $cmd $reps) $vars
    if ($base == null) or ($run == null) { return {case: $label, cpu_per: null} }
    { case: $label
      reps: $reps
      cpu_total: (($run.cpu * 1000 | math round) * 1ms)
      cpu_per: ((($run.cpu - $base.cpu) / $reps * 1_000_000 | math round) * 1µs)
      wall_per: ((($run.real - $base.real) / $reps * 1_000_000 | math round) * 1µs) }
}

# ── span: nu's own parse/eval attribution ─────────────────────────────────────

export def span [
    label: string
    code: string
    --rounds: int = 15
    --warmup: int = 5
    --name: string = "evaluate_commands"
    --flags: list<string> = ["-n" "--no-std-lib"]
    --vars: record = {}
] {
    let times = with-env $vars {
        for _ in 1..$warmup { ^$NU ...$flags -c $code | complete | ignore }
        1..$rounds | each {
            let r = ^$NU ...$flags --log-level perf -c $code | complete
            $r.stderr | lines | where {|l| $l =~ $name } | get -o 0 | default ""
            | parse --regex 'took (?<d>[0-9.]+\s*(ms|µs|ns|sec|s))$' | get -o 0.d
        } | compact | each { $in | into duration }
    }
    stats $label $times
}

# ── in-process: for store ops and pure functions ──────────────────────────────

export def inproc [
    label: string
    code: closure
    --rounds: int = 200
    --warmup: int = 20
] {
    for _ in 1..$warmup { do $code | ignore }
    stats $label (1..$rounds | each { timeit { do $code | ignore } })
}
