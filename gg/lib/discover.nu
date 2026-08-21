use config.nu

# Run a git command in a repo, returning trimmed stdout ("" on failure).
# Args are passed as a list (so flags like --short aren't parsed as git-out's own).
def git-out [repo: path, args: list<string>]: nothing -> string {
  let r = (^git -C $repo ...$args | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { "" }
}

# Discover cloned repos under the configured source(s). Pure-local: no API calls.
# Provider is taken from config (not sniffed). Returns:
#   { source, provider, name, path, remote, default_branch }
# where `name` is the repo path relative to the source dir and `path` is absolute.
export def main [source?: string]: nothing -> table {
  config resolve $source | each {|src|
    if not ($src.dir | path exists) { return [] }
    glob ($src.dir | path join "**/.git" | into glob)
    | each {|gitpath|
        let repo = ($gitpath | path dirname)
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
