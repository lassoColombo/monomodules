# Working-tree status of one repo: one `git status --porcelain=2 --branch` call
# (branch, ahead/behind vs upstream, dirty file count) plus a stash count.
# Shared by `status` and `sync`.
export def repo-status [repo: path]: nothing -> record {
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
