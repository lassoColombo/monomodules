use ../lib/discover.nu

def source-completer [] { $env.gg_config? | default {} | columns }

# Working-tree status of one repo: one `git status --porcelain=2 --branch` call
# (branch, ahead/behind vs upstream, dirty file count) plus a stash count.
def repo-status [repo: path]: nothing -> record {
  let r = (^git -C $repo status --porcelain=2 --branch | complete)
  if $r.exit_code != 0 {
    return { branch: "?", ahead: 0, behind: 0, dirty: 0, stash: 0 }
  }
  let ls = ($r.stdout | lines)
  let branch = ($ls | where {|l| $l | str starts-with "# branch.head "} | get 0? | default "# branch.head ?" | str replace "# branch.head " "")
  let ab = ($ls | where {|l| $l | str starts-with "# branch.ab "} | get 0? | default "")
  let ahead = (if ($ab | is-empty) { 0 } else { ($ab | parse "# branch.ab +{a} -{b}").0.a | into int })
  let behind = (if ($ab | is-empty) { 0 } else { ($ab | parse "# branch.ab +{a} -{b}").0.b | into int })
  let dirty = ($ls | where {|l| not ($l | str starts-with "#")} | length)
  let stash = (^git -C $repo stash list | complete | get stdout | lines | where {|l| ($l | str trim) != ""} | length)
  { branch: $branch, ahead: $ahead, behind: $behind, dirty: $dirty, stash: $stash }
}

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
