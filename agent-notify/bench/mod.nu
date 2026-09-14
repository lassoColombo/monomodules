# The measurement harness, and the cases that produced plan.md §3.
#
# Kept in the repo rather than in a scratch directory because §8 promises that
# every step re-measures against the baseline, and a harness that evaporates
# between sessions cannot keep that promise. It is NOT part of the module:
# nothing in ../mod.nu imports it, so `use agent-notify` never parses a byte of
# it.
#
#   use agent-notify/bench
#   bench floor        process floor + the `use` ladder
#   bench parse slope  the ms-per-KB slope; `parse comments`, `parse entry`
#   bench work         zellij / sketchybar / pandoc costs
#   bench rate         how often hooks actually fire, from real transcripts
#   bench v2           the end-to-end cost per event — the number to protect
#   bench aerospace-windows
#                      can aerospace be a session-container? step 12 phase 1
#
# `v1.nu` and `store_bench.nu` measured the OLD module and retired with it at
# the cutover, as this file always said they would. The numbers they produced
# are not lost — they are plan.md §3, which is where a baseline belongs once the
# thing it measured is gone.
export use floor.nu
export use parse.nu
export use work.nu
export use rate.nu
export use v2.nu
export use aerospace-windows.nu
