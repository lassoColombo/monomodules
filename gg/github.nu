use merge-request.nu

def source-branch-completer [] {[main]}
def target-branch-completer [] {[main master]}

# Opens a pull request for the current repo (launch in project root)
export def pull-request [
  source_branch: string@source-branch-completer
  target_branch: string@target-branch-completer
  --title (-t): string             # PR title (auto-generated if omitted)
  --description (-d): string       # PR description (auto-generated if omitted)
  --yes                            # Do not ask for confirmation
  --reviewers: list<string> = []   # Reviewer logins
  --draft                          # Create as draft pull request
  --think                          # Use extended thinking when generating the content
] {
  let content = merge-request generate-mr-content $source_branch $target_branch --title $title --description $description --yes=$yes --think=$think
  if ($content == null) { return }

  let reviewer_args = if ($reviewers | is-not-empty) { ["--reviewer" ($reviewers | str join ',')] } else { [] }
  let draft_args = if $draft { ["--draft"] } else { [] }

  let args = [
    "--title" $content.title
    "--body" $content.description
    "--base" $target_branch
    "--head" $source_branch
  ] ++ $reviewer_args ++ $draft_args

  gh pr create ...$args
}

# Fetches all repos in a github org
def fetch-org-repos [org: string]: nothing -> table {
  gh repo list $org --limit 4000 --json nameWithOwner,sshUrl | from json
}

# Lists all repos in a github org
export def list-repos [org: string] {
  fetch-org-repos $org | get nameWithOwner
}

# Clones a whole github org mirroring the tree structure
export def clone-org [org: string] {
  fetch-org-repos $org | each {|r|
    let dir = $r.nameWithOwner
    if ($dir | path exists) {
      return
    }
    let dirname = $dir | path dirname
    mkdir $dirname
    git clone $r.sshUrl $dir
  }
}
