# Case group 5 — THE EVENT RATE: how often the hot path actually fires.
#
# A per-event cost only matters multiplied by a rate, and the rate is the one
# quantity we have been guessing at ("PostToolUse fires on every tool call").
# Real transcripts know the answer: every `tool_use` block an assistant emitted
# is one PostToolUse, and its timestamp says when. Parallel blocks in a single
# assistant message each fire their own hook, so blocks are counted, not
# messages.
#
# What matters for the design is not the average — it is the BURST: the most
# events that ever land inside one second, because that is the moment the hook
# path is competing with the agent it is describing.

const PROJECTS = ($nu.home-dir | path join ".claude" "projects")

# tool_use timestamps from one transcript, as a list of unix seconds (float).
def tool-times [file: string] {
    let raw = try {
        ^jq -r '
            select(.type == "assistant")
            | .timestamp as $t
            | [.message.content[]? | select(.type == "tool_use")] | length as $n
            | select($n > 0) | "\($t) \($n)"
        ' $file | complete
    } catch { null }
    if ($raw == null) or ($raw.exit_code != 0) { return [] }
    $raw.stdout | lines | where {|l| ($l | str trim) != "" } | each {|l|
        let p = $l | split row " "
        let ts = try { $p.0 | into datetime | into int } catch { null }
        if ($ts == null) { null } else { {t: ($ts / 1_000_000_000), n: ($p.1 | into int)} }
    } | compact
}

# Per-transcript summary. `burst` is the largest number of events in any one
# second; `p50_gap` the median spacing between consecutive events.
def summarise [file: string] {
    let ev = tool-times $file
    if (($ev | length) < 20) { return null }
    let total = $ev | get n | math sum
    let ts = $ev | get t
    let span = ($ts | math max) - ($ts | math min)
    let gaps = $ts | window 2 | each {|w| ($w.1 - $w.0) }
    # events per second, bucketed — the peak bucket is the burst.
    let buckets = $ev | group-by {|e| ($e.t | math round | into string) }
    let burst = $buckets | values | each {|b| $b | get n | math sum } | math max
    { file: ($file | path basename | str substring 0..7)
      events: $total
      span_min: (($span / 60 * 10 | math round) / 10)
      per_min: ((($total / ($span / 60)) * 10 | math round) / 10)
      p50_gap_s: (($gaps | where {|g| $g > 0 } | math median | default 0) | math round --precision 2)
      burst_per_s: $burst }
}

# The per-transcript rate is bounded by something no amount of engineering will
# change: a tool call costs the model a second or two to emit, so ONE agent can
# never make the hook path hot. Concurrency is the only thing that can — several
# agents, each with their own subagents, all firing into the same machine. So
# the real question is the SYSTEM-WIDE burst: pool every transcript's events on
# one wall prune-daemon and look at the busiest seconds that have ever actually
# happened.
export def global [--days: int = 21] {
    let cutoff = (date now) - ($days * 1day)
    let files = ls ($"($PROJECTS)/**/*.jsonl" | into glob)
        | where modified > $cutoff and size > 20kb
        | get name
    print $"pooling ($files | length) transcripts from the last ($days) days..."

    let all = $files | each {|f| tool-times $f } | flatten
    if ($all | is-empty) { print "no events"; return }

    let per_sec = $all | group-by {|e| ($e.t | math round | into string) }
        | values | each {|b| $b | get n | math sum }
    let busy_min = $all | group-by {|e| (($e.t / 60) | math round | into string) }
        | values | each {|b| $b | get n | math sum }

    print ({
        events_total: ($all | get n | math sum)
        seconds_with_any_event: ($per_sec | length)
        events_per_busy_second_p50: ($per_sec | math median)
        events_per_busy_second_max: ($per_sec | math max)
        events_per_busy_minute_p50: ($busy_min | math median)
        events_per_busy_minute_max: ($busy_min | math max)
    })
    print ""
    print "busiest seconds, by event count (how many hooks landed together):"
    print ($per_sec | uniq --count | sort-by value --reverse | first 8 | table)
}

export def main [--limit: int = 12] {
    let files = ls ($"($PROJECTS)/**/*.jsonl" | into glob)
        | where size > 150kb
        | sort-by modified --reverse
        | first $limit
        | get name
    let rows = $files | each {|f| summarise $f } | compact
    print ($rows | table --width 110)
    print ""
    print "── across those transcripts ─────────────────────────────────────────"
    print ({
        transcripts: ($rows | length)
        total_events: ($rows | get events | math sum)
        median_events_per_min: ($rows | get per_min | math median)
        median_gap_s: ($rows | get p50_gap_s | math median)
        worst_burst_per_s: ($rows | get burst_per_s | math max)
        median_burst_per_s: ($rows | get burst_per_s | math median)
    })
}
