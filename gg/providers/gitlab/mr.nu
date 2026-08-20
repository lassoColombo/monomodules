use ../../lib/mr-content.nu generate-mr-content

def source-branch-completer [] {[quality]}
def target-branch-completer [] {[main master quality]}

# Opens a merge request for the current repo (launch in project root)
export def main [
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
  let content = generate-mr-content $source_branch $target_branch --title $title --description $description --yes=$yes --think=$think
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
