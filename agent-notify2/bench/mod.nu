# The measurement harness, and the cases that produced plan.md §3.
#
# Kept in the repo rather than in a scratch directory because §8 promises that
# every step re-measures against the baseline, and a harness that evaporates
# between sessions cannot keep that promise. It is NOT part of the module: nothing
# in ../mod.nu imports it, so `use agent-notify2` never parses a byte of it.
#
#   use agent-notify2/bench
#   bench floor        process floor + the `use` ladder
#   bench parse slope  the ms-per-KB slope; `parse comments`, `parse entry`
#   bench work         zellij / sketchybar / pandoc costs
#   bench rate         how often hooks actually fire, from real transcripts
#   bench v1           v1's end-to-end cost — the baseline to beat
#   bench v2           v2's end-to-end cost — the number to protect
#
# `store_bench` measures v1's store and retires with v1 at cutover.
export use floor.nu
export use parse.nu
export use work.nu
export use rate.nu
export use v1.nu
export use v2.nu
export use store_bench.nu
