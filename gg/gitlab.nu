use merge-request.nu

def source-branch-completer [] {[quality]}
def target-branch-completer [] {[main master quality]}

# Opens a merge request for the current repo (launch in project root)
export def merge-request [
  source_branch: string@source-branch-completer
  target_branch: string@target-branch-completer
  --title (-t): string             # MR title (auto-generated if omitted)
  --description (-d): string       # MR description (auto-generated if omitted)
  --yes                            # Do not ask for confirmation
  --reviewers: list<string> = []   # Reviewer usernames
  --assignee: string               # Assignee username (e.g. @me)
  --draft                          # Mark merge request as draft
  --think                          # Use extended thinking when generating the content
] {
  let content = merge-request generate-mr-content $source_branch $target_branch --title $title --description $description --yes=$yes --think=$think
  if ($content == null) { return }

  let reviewer_args = if ($reviewers | is-not-empty) { ["--reviewer" ($reviewers | str join ',')] } else { [] }
  let assignee_args = if ($assignee != null) { ["--assignee" $assignee] } else { [] }
  let draft_args = if $draft { ["--draft"] } else { [] }

  let args = [
    "--source-branch" $source_branch
    "--target-branch" $target_branch
    "--title" $content.title
    "--description" $content.description
    "--yes"
  ] ++ $reviewer_args ++ $assignee_args ++ $draft_args

  glab mr create ...$args
}

# Fetches all projects in a gitlab group (paginated)
def fetch-group-projects [group_id: string, hostname: string]: nothing -> table {
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

# Lists all repos in a gitlab group
export def list-repos [
  group_id: string
  --hostname: string = "git.elmec.com"  # GitLab host
] {
  fetch-group-projects $group_id $hostname | get path_with_namespace
}

# Clones a whole gitlab group mirroring the tree structure
export def clone-group [
  group_id: string
  --hostname: string = "git.elmec.com"  # GitLab host
] {
  fetch-group-projects $group_id $hostname | each {|p|
    let dir = $p.path_with_namespace
    if ($dir | path exists) {
      return
    }
    let dirname = $dir | path dirname
    mkdir $dirname
    git clone $p.ssh_url_to_repo $dir
  }
}
