use fetch.nu

# Clones a whole gitlab group mirroring the tree structure
export def main [
  group_id: string
  --hostname: string = "git.elmec.com"  # GitLab host
] {
  fetch $group_id $hostname | each {|p|
    let dir = $p.path_with_namespace
    if ($dir | path exists) {
      return
    }
    let dirname = $dir | path dirname
    mkdir $dirname
    git clone $p.ssh_url_to_repo $dir
  }
}
