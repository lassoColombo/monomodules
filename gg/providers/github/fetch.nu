# Fetches all repos in a github org.
# Internal to the github provider — used by `list` and `clone`, not exported.
export def main [org: string]: nothing -> table {
  gh repo list $org --limit 4000 --json nameWithOwner,sshUrl | from json
}
