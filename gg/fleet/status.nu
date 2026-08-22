use ../lib/discover.nu
use ../lib/gitstate.nu repo-status

def source-completer [] { $env.gg_config? | default {} | columns }

# Read-only overview of the fleet: current branch, ahead/behind upstream, dirty
# file count, and stash count — one row per repo. Omit `source` for all sources.
# `--dirty` shows only repos needing attention (dirty / ahead / behind / stashed).
export def main [
  source?: string@source-completer
  --dirty (-d)   # only repos that are dirty, ahead, behind, or have stashes
]: nothing -> table {
  let rows = (
    discover $source
    | par-each {|r| { source: $r.source, repo: $r.name } | merge (repo-status $r.path) }
    | sort-by source repo
  )
  let n  = ($rows | length)
  let nd = ($rows | where dirty  > 0 | length)
  let na = ($rows | where ahead  > 0 | length)
  let nb = ($rows | where behind > 0 | length)
  let ns = ($rows | where stash  > 0 | length)
  print -e $"(ansi cyan_bold)($n) repos(ansi reset)  (ansi yellow_bold)($nd) dirty(ansi reset)  (ansi green_bold)($na) ahead(ansi reset)  (ansi red_bold)($nb) behind(ansi reset)  (ansi grey)($ns) stashed(ansi reset)"

  if $dirty {
    $rows | where {|x| $x.dirty > 0 or $x.ahead > 0 or $x.behind > 0 or $x.stash > 0 }
  } else {
    $rows
  }
}
