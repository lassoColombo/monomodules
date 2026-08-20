use fetch.nu

# Lists all repos in a gitlab group
export def main [
  group_id: string
  --hostname: string = "git.elmec.com"  # GitLab host
] {
  fetch $group_id $hostname | get path_with_namespace
}
