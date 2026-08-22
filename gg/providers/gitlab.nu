# GitLab adapter — enumerate a source's projects via `glab` (paginated).
# Returns table<{path, ssh_url}> where `path` is RELATIVE to the source group
# (the group's own prefix stripped, subgroups preserved) — so each project maps
# directly to `<dir>/<path>` on disk. The only gitlab-specific fleet code.

# Strip a group's own path prefix from a project's full path_with_namespace,
# yielding a path relative to the group (subgroups preserved). Pure & testable.
export def strip-group [group_path: string]: string -> string {
  let full = $in
  if ($full | str starts-with $"($group_path)/") { $full | str replace $"($group_path)/" "" } else { $full }
}

export def enumerate [source: record]: nothing -> table {
  let group = ($source.group_id? | default ($source.group?))
  if ($group == null) {
    error make --unspanned {msg: $"gg: gitlab source '($source.name)' needs 'group' or 'group_id'"}
  }
  # `group` may be a numeric id or a path like "a/b" — url-encode slashes for the API path.
  let group_enc = ($group | into string | str replace --all "/" "%2F")

  # Canonical group path — the prefix to strip so project paths become group-relative.
  # Resolving it via the API works whether `group` is a path or a numeric group_id.
  let group_path = (glab api $"groups/($group_enc)" --hostname $source.host | from json | get full_path)

  mut page = 1
  mut out = []
  loop {
    let batch = (glab api $"groups/($group_enc)/projects" --hostname $source.host -X GET -F include_subgroups=true -F per_page=100 -F $"page=($page)" | from json)
    if ($batch | is-empty) { break }
    $out = ($out ++ $batch)
    $page = ($page + 1)
  }

  $out | each {|p| { path: ($p.path_with_namespace | strip-group $group_path), ssh_url: $p.ssh_url_to_repo } }
}
