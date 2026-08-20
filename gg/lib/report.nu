# Result contract + reporting for bulk fleet operations.
#
# PROVISIONAL (Step 1): shape is planted now and finalized when the first verb,
# `status` (Step 4), exercises it. Every bulk verb returns the full table and
# prints a one-line colored summary — matching the commit / MR display style.
#
# Contract:
#   list<record<repo: string, status: string, detail: string>>
#   status ∈ "ok" | "skip" | "fail"

# Print a one-line colored tally of a results table (see contract above).
export def summary []: table -> nothing {
  let rows = $in
  let ok   = ($rows | where status == "ok"   | length)
  let skip = ($rows | where status == "skip" | length)
  let fail = ($rows | where status == "fail" | length)
  print $"(ansi green_bold)✓ ($ok) ok(ansi reset)  (ansi yellow_bold)⤳ ($skip) skipped(ansi reset)  (ansi red_bold)✗ ($fail) failed(ansi reset)  (ansi grey)\(($rows | length) total\)(ansi reset)"
}
