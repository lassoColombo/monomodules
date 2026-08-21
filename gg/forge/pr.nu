use lib/mr-content.nu generate-mr-content

def source-branch-completer [] {[main]}
def target-branch-completer [] {[main master]}

# Opens a GitHub pull request for the current repo (launch in project root)
export def main [
  source_branch: string@source-branch-completer
  target_branch: string@target-branch-completer
  --title (-t): string             # PR title (auto-generated if omitted)
  --description (-d): string       # PR description (auto-generated if omitted)
  --yes                            # Do not ask for confirmation
  --reviewers: list<string> = []   # Reviewer logins
  --draft                          # Create as draft pull request
  --think                          # Use extended thinking when generating the content
] {
  let content = generate-mr-content $source_branch $target_branch --title $title --description $description --yes=$yes --think=$think
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
