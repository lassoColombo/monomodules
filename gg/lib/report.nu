# Result contract + reporting for bulk fleet operations.
#
# Bulk verbs (each, status, …) return a table that MUST include a `status`
# column ∈ "ok" | "skip" | "fail"; other columns are verb-specific. `summary`
# prints a one-line colored tally to stderr (so stdout stays pipeable), matching
# the commit / MR display style.

# Print a one-line colored tally of a results table to stderr.
export def summary []: table -> nothing {
  let rows = $in
  let ok   = ($rows | where status == "ok"   | length)
  let skip = ($rows | where status == "skip" | length)
  let fail = ($rows | where status == "fail" | length)
  print -e $"(ansi green_bold)✓ ($ok) ok(ansi reset)  (ansi yellow_bold)⤳ ($skip) skipped(ansi reset)  (ansi red_bold)✗ ($fail) failed(ansi reset)  (ansi grey)\(($rows | length) total\)(ansi reset)"
}
