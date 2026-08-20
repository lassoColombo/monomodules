use fetch.nu

# Clones a whole github org mirroring the tree structure
export def main [org: string] {
  fetch $org | each {|r|
    let dir = $r.nameWithOwner
    if ($dir | path exists) {
      return
    }
    let dirname = $dir | path dirname
    mkdir $dirname
    git clone $r.sshUrl $dir
  }
}
