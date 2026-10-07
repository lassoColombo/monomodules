# kube-bridge/lib/config — the cluster file, `~/.config/kube-bridge/clusters.yaml`.
#
# One `clusters:` list, in match order: the first entry whose `hosts` pattern
# matches the host argument wins and is merged over DEFAULTS, so an entry spells
# out only what differs from a stock kubeadm cluster.
#
#   clusters:
#     - name: homelab
#       hosts: '^k3s-'
#       remote_kubeconfig: /etc/rancher/k3s/k3s.yaml
#
# The file is the whole of the configuration except the closures, which live in
# $env.kubebridge_config — see lib/hooks.nu.

use ./paths.nu

# Built-in cluster defaults, used for every field a matching entry leaves out —
# and for every host that matches no entry at all, which is exactly right for a
# stock kubeadm cluster reachable as its own SSH host.
const DEFAULTS = {
  remote_kubeconfig: "/etc/kubernetes/admin.conf"
  remote_apiserver_port: 6443
  sudo: false
  kube_binary: "kubectl"
}

export def "defaults" []: nothing -> record { $DEFAULTS }

# The configured clusters, in file order. Empty when the file doesn't exist yet,
# so an unconfigured kube-bridge is a working kube-bridge.
export def "list" []: nothing -> list {
  let f = paths clusters-file
  if ($env.kubebridge_config?.clusters? | is-not-empty) {
    error make --unspanned {msg: $"`$env.kubebridge_config.clusters` is no longer read — move the clusters to ($f) \(`kube-bridge clusters edit`), and leave only `completion` / `hooks` closures in the environment."}
  }
  if not ($f | path exists) { return [] }
  let doc = open $f
  if ($doc | is-empty) { return [] }
  if not (($doc | describe) | str starts-with "record") {
    error make --unspanned {msg: $"($f): expected a YAML mapping with a `clusters:` list at its top level"}
  }
  if ("clusters" not-in ($doc | columns)) {
    error make --unspanned {msg: $"($f) has no `clusters:` list"}
  }
  let clusters = $doc.clusters | default []
  if not (($clusters | describe) =~ '^(list|table)') {
    error make --unspanned {msg: $"($f): `clusters:` must be a list of entries, written in match order"}
  }
  $clusters
}

# Does this entry claim `host`? `hosts` is a regex string, or a list of them —
# any one matching is enough.
def claims [host: string]: record -> bool {
  let entry = $in
  let patterns = $entry | get -o hosts
  if ($patterns | is-empty) { return false }
  let patterns = if (($patterns | describe) == "string") { [$patterns] } else { $patterns }
  $patterns | any {|p|
    if (($p | describe) != "string") {
      let who = $entry | get -o name | default "<unnamed>"
      error make --unspanned {msg: $"cluster ($who): `hosts` must be a regex string or a list of them"}
    }
    $host =~ $p
  }
}

# The cluster record that governs `host`: the first entry claiming it, merged
# over the defaults — or the bare defaults when no entry does.
export def "for-host" [host: string]: nothing -> record {
  let matched = list | where {|c| $c | claims $host } | first
  $DEFAULTS | merge ($matched | default {})
}

# Names of the configured clusters, for completion.
export def "names" []: nothing -> list<string> {
  list | each {|c| $c | get -o name } | compact
}
