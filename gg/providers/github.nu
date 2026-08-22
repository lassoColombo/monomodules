# GitHub adapter — enumerate a source's repos via `gh`.
# Returns table<{path, ssh_url}> where `path` is the repo RELATIVE to the owner
# (owner segment stripped). GitHub orgs are flat, so this is just the repo name —
# mapping directly to `<dir>/<path>` on disk. The only github-specific fleet code.

# Strip the owner segment from an "owner/repo" name, yielding the repo path
# relative to the owner. Pure & testable.
export def strip-owner []: string -> string {
  $in | split row "/" | skip 1 | str join "/"
}

export def enumerate [source: record]: nothing -> table {
  let org = ($source.org? | default ($source.group?))
  if ($org == null) {
    error make --unspanned {msg: $"gg: github source '($source.name)' needs 'org'"}
  }
  gh repo list $org --limit 4000 --json nameWithOwner,sshUrl
  | from json
  | each {|r| { path: ($r.nameWithOwner | strip-owner), ssh_url: $r.sshUrl } }
}
