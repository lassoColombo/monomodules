# Fetches all projects in a gitlab group (paginated).
# Internal to the gitlab provider — used by `list` and `clone`, not exported.
export def main [group_id: string, hostname: string]: nothing -> table {
  mut page = 1
  mut out = []
  loop {
    let batch = glab api $"groups/($group_id)/projects" --hostname $hostname -X GET -F include_subgroups=true -F per_page=100 -F $"page=($page)" | from json
    if ($batch | is-empty) { break }
    $out = $out ++ $batch
    $page = $page + 1
  }
  $out
}
