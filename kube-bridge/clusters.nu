# kube-bridge/clusters.nu — the cluster-config commands. Composed by mod.nu as
# `kube-bridge clusters …`, so the leaf names here stay bare (`show`, `file`, …).

use ./lib/config.nu
use ./lib/paths.nu
use ./lib/hosts.nu

# The skeleton written on the first `clusters edit`, so an empty config is still
# a documented one.
const TEMPLATE = "# kube-bridge clusters — ~/.config/kube-bridge/clusters.yaml
#
# Entries are tried in order and the first whose `hosts` pattern matches the host
# argument wins. Every field is optional: what you leave out falls back to the
# built-in defaults (`kube-bridge clusters defaults`), which already describe a
# stock kubeadm cluster, so a host that matches nothing still works.
#
#   name                   what to call this cluster (documentation only)
#   hosts                  regex matched against the host argument, or a list of regexes
#   remote_kubeconfig      kubeconfig path ON THE REMOTE            (/etc/kubernetes/admin.conf)
#   remote_apiserver_port  port the apiserver listens on, remotely  (6443)
#   sudo                   read that kubeconfig, and run kubectl, under sudo  (false)
#   kube_binary            the remote kubectl invocation            (kubectl)

clusters:
  # - name: homelab
  #   hosts: '^k3s-'
  #   remote_kubeconfig: /etc/rancher/k3s/k3s.yaml
  #
  # - name: lab
  #   hosts: ['^k8s-node-', '^k8s-cp-']
  #   sudo: true
"

# Show the configured clusters, exactly as the file spells them.
#
# Returns the `clusters:` list in match order — the order itself is meaningful,
# since the first entry matching a host wins. With a name, returns that single
# entry (or null). Fields an entry omits are not filled in here: see
# `kube-bridge clusters defaults` for what they fall back to, or
# `kube-bridge clusters resolve <host>` for the merged record a host actually gets.
@category kubernetes
@search-terms clusters config show list configuration yaml
@example "every configured cluster, in match order" { kube-bridge clusters show }
@example "one cluster by name" { kube-bridge clusters show homelab }
export def "show" [
  name?: string@"config names"   # cluster to show; omit for all of them
] {
  if ($name | is-empty) { return (config list) }
  config list | where {|c| ($c | get -o name) == $name } | first
}

# The built-in cluster defaults — every field a cluster entry may leave out.
@category kubernetes
@search-terms clusters defaults fallback config
@example "what an omitted field falls back to" { kube-bridge clusters defaults } --result {remote_kubeconfig: "/etc/kubernetes/admin.conf", remote_apiserver_port: 6443, sudo: false, kube_binary: "kubectl"}
export def "defaults" []: nothing -> record { config defaults }

# Show the cluster record a host actually resolves to.
#
# Runs the same match `apiserver` and `service` run — first entry whose `hosts`
# pattern matches, merged over the defaults — and hands back the merged record.
# The answer to "why is it reading the wrong kubeconfig": either a pattern is
# catching the host earlier than you meant, or none is and you're seeing the
# defaults.
@category kubernetes
@search-terms clusters resolve match host which cluster debug
@example "which cluster governs this host" { kube-bridge clusters resolve k3s-01 } --result {remote_kubeconfig: "/etc/rancher/k3s/k3s.yaml", remote_apiserver_port: 6443, sudo: false, kube_binary: "kubectl", name: "homelab", hosts: "^k3s-"}
export def "resolve" [
  host: string@"hosts suggest"   # ssh target to match against the cluster patterns
]: nothing -> record {
  config for-host $host
}

# Absolute path to the clusters file (`~/.config/kube-bridge/clusters.yaml`).
@category kubernetes
@search-terms clusters file path config yaml where
@example "print the clusters file path" { kube-bridge clusters file }
export def "file" []: nothing -> string { paths clusters-file }

# Absolute path to the config directory (`~/.config/kube-bridge`).
@category kubernetes
@search-terms clusters dir directory config path
@example "print the config directory path" { kube-bridge clusters dir }
export def "dir" []: nothing -> string { paths config-dir }

# Open the clusters file in $EDITOR, seeding a commented skeleton on first use.
@category kubernetes
@search-terms clusters edit config open editor yaml
@example "edit the clusters file" { kube-bridge clusters edit }
export def "edit" [] {
  let f = paths clusters-file
  paths ensure-dir ($f | path dirname)
  if not ($f | path exists) { $TEMPLATE | save --force $f }
  # $EDITOR may carry flags ("code -w"), so split the command off its arguments
  # and launch it directly — no `nu -c`, whose quoting mangles a path with spaces.
  let editor = $env.EDITOR? | default "vi" | split row " " | where ($it | str length) > 0
  ^($editor | first) ...($editor | skip 1) $f
}
