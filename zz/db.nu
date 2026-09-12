# zoxide itself. Every call that shells out to the binary lives here, and none of
# them decides what to do with what comes back — that is mod.nu's, and picking
# one of them is pick/'s.
#
# The writes stay quiet: `prune` hands back what it removed rather than printing
# it, so the one place that talks to a human is the command surface.

# List zoxide entries as a table of { score, path }.
# Keywords narrow results the same way `zoxide query` does.
export def entries [
  ...keywords: string  # narrow results by matching keywords
  --all(-a)            # include unavailable directories
  --base-dir: string   # only search within this directory
  --exclude: string    # exclude the given directory
]: nothing -> table<score: float, path: string> {
  (^zoxide query
    --list
    --score
    ...(if $all { [--all] } else { [] })
    ...(if ($base_dir | is-not-empty) { [--base-dir $base_dir] } else { [] })
    ...(if ($exclude | is-not-empty) { [--exclude $exclude] } else { [] })
    ...$keywords)
  | lines
  | parse --regex '^\s*(?<score>[\d.]+)\s+(?<path>.+)$'
  | update score { into float }
}

# Add a directory to the database.
export def add [path: string] {
  ^zoxide add $path
}

# Forget directories. Nothing to forget is not an error — `zoxide remove` with no
# arguments is, so the guard belongs here rather than at every call site.
export def remove [...paths: string] {
  if ($paths | is-empty) { return }
  ^zoxide remove ...$paths
}

# Forget every entry whose directory is gone, and hand back what went.
export def prune []: nothing -> list<string> {
  let stale = (entries --all | where { |e| not ($e.path | path exists) } | get path)
  remove ...$stale
  $stale
}
