use fetch.nu

# Lists all repos in a github org
export def main [org: string] {
  fetch $org | get nameWithOwner
}
