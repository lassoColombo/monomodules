# GitLab adapter — enumerate a source's projects via `glab` (paginated).
# The only gitlab-specific fleet code. Returns a normalized table<{path, ssh_url}>.
export def enumerate [source: record]: nothing -> table {
  let group = ($source.group_id? | default ($source.group?))
  if ($group == null) {
    error make --unspanned {msg: $"gg: gitlab source '($source.name)' needs 'group' or 'group_id'"}
  }
  # group may be a numeric id or a path like "a/b" — url-encode slashes for the API path.
  let group = ($group | into string | str replace --all "/" "%2F")

  mut page = 1
  mut out = []
  loop {
    let batch = (glab api $"groups/($group)/projects" --hostname $source.host -X GET -F include_subgroups=true -F per_page=100 -F $"page=($page)" | from json)
    if ($batch | is-empty) { break }
    $out = ($out ++ $batch)
    $page = ($page + 1)
  }
  $out | select path_with_namespace ssh_url_to_repo | rename path ssh_url
}
