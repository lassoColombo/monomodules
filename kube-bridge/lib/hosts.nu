# kube-bridge/lib/hosts — what the `<host>` argument completes to.
# Shared by the bridge commands and `kube-bridge clusters resolve`.

use ./hooks.nu

# Every host named in ~/.ssh/known_hosts, deduplicated.
def known-hosts []: nothing -> list<string> {
  let p = [$nu.home-dir ".ssh/known_hosts"] | path join
  if not ($p | path exists) { return [] }
  open $p
  | lines
  | str trim
  | where ($it | str length) > 0
  | where not ($it | str starts-with "#")
  | split column -r '\s+' host
  | get host
  | where ($it | str length) > 0
  | uniq
}

# Suggestions for a `<host>` argument: the `completion.hosts` closure when one is
# registered, else known_hosts.
export def "suggest" []: nothing -> list<string> {
  let custom = hooks completion "hosts"
  if ($custom != null) { do $custom } else { known-hosts }
}
