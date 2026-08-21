use config.nu

# Run a git command in a repo, returning trimmed stdout ("" on failure).
# Args are passed as a list (so flags like --short aren't parsed as git-out's own).
def git-out [repo: path, args: list<string>]: nothing -> string {
  let r = (^git -C $repo ...$args | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

# Find the top-most git repos under a root. Walks directories but STOPS descending
# the moment a repo (.git) is found — so a repo's own working tree, its nested
# worktrees (.claude/worktrees/…), and submodules are never traversed. This keeps
# it fast over large trees and yields only real fleet repos. `ls` skips dotfiles,
# so .git/.claude are never entered.
def find-repos [root: path]: nothing -> list<string> {
  mut stack = [($root | into string)]
  mut repos = []
  while ($stack | is-not-empty) {
    let dir = ($stack | last)
    $stack = ($stack | drop)
    let dotgit = ($dir | path join ".git")
    if ($dotgit | path exists) {
      # git-managed: record only a normal clone (.git is a directory). A .git
      # *file* means a worktree or submodule — skip it. Either way, stop here.
      if (($dotgit | path type) == "dir") { $repos = ($repos | append $dir) }
    } else if (($dir | path basename) | str ends-with ".git") {
      # bare repo (e.g. foo.git) — skip, and don't descend into its object store.
    } else {
      let subs = (try { ls $dir | where type == "dir" | get name } catch { [] })
      $stack = ($stack | append $subs)
    }
  }
  $repos
}

# Discover cloned repos under the configured source(s). Pure-local: no API calls.
# Provider is taken from config (not sniffed). Returns:
#   { source, provider, name, path, remote, default_branch }
# where `name` is the repo path relative to the source dir and `path` is absolute.
export def main [source?: string]: nothing -> table {
  config resolve $source | each {|src|
    if not ($src.dir | path exists) { return [] }
    find-repos $src.dir | each {|repo|
      let remote = (git-out $repo ["remote" "get-url" "origin"])
      let head = (git-out $repo ["symbolic-ref" "--short" "refs/remotes/origin/HEAD"])
      {
        source: $src.name
        provider: $src.provider
        name: ($repo | path relative-to $src.dir)
        path: $repo
        remote: $remote
        default_branch: ($head | str replace "origin/" "")
      }
    }
  } | flatten
}
