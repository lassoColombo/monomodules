# GitHub adapter — enumerate a source's repos via `gh`.
# The only github-specific fleet code. Returns a normalized table<{path, ssh_url}>.
export def enumerate [source: record]: nothing -> table {
  let org = ($source.org? | default ($source.group?))
  if ($org == null) {
    error make --unspanned {msg: $"gg: github source '($source.name)' needs 'org'"}
  }
  gh repo list $org --limit 4000 --json nameWithOwner,sshUrl
  | from json
  | select nameWithOwner sshUrl
  | rename path ssh_url
}
