use ../lib/discover.nu
use ../lib/report.nu

def source-completer [] { $env.gg_config? | default {} | columns }

# Run a closure in every repo of the configured fleet, in parallel.
#
# The closure runs with the repo as its working directory and receives the repo
# record ({source, provider, name, path, remote, default_branch}) as pipeline
# input ($in). Errors are isolated per repo — one failure never aborts the run.
#
# Returns a {source, repo, status, output} table (status ∈ ok|fail) and prints a
# colored tally to stderr. Omit --source to run across every configured source.
#
# Examples:
#   gg each { git pull --ff-only }                # update the whole fleet
#   gg each -s elmec { git switch main }          # one source
#   gg each { git rev-parse --abbrev-ref HEAD }   # ad-hoc query -> table
export def main [
  action: closure
  --source (-s): string@source-completer
] {
  let repos = (if $source == null { discover } else { discover $source })
  let results = (
    $repos
    | par-each {|r|
        let outcome = try {
          cd $r.path
          { status: "ok", output: ($r | do $action) }
        } catch {|e| { status: "fail", output: $e.msg } }
        { source: $r.source, repo: $r.name } | merge $outcome
      }
    | sort-by source repo
  )
  $results | report summary
  $results
}
