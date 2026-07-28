# Manage SSH-based bridges (port forwards) to remote machines for kubernetes use.
#
# Two primary use cases:
#   1. `kube-bridge service <host> <ns/svc>` — forward a k8s Service from a
#      remote cluster to a local port.
#   2. `kube-bridge apiserver <host>` — forward the kube-apiserver of a remote
#      machine to a local port, plus expose a patched kubeconfig.
#
# Bridges are managed via SSH ControlMaster sockets (one master per host,
# kept alive by `ControlPersist=yes`). State is persisted to JSON so `list`
# and `kill` work from any shell.
#
# Configuration is taken from `$env.kubebridge_config`. See README for shape.

# ----------------------
#  Config access
# ----------------------

def kubebridge-config [] {
  $env.kubebridge_config? | default {}
}

# Built-in cluster defaults. Used for any field the user hasn't set in a
# matching cluster record (or when no cluster matches a host).
const CLUSTER_DEFAULTS = {
  remote_kubeconfig: "/etc/kubernetes/admin.conf"
  remote_apiserver_port: 6443
  sudo: false
  kube_binary: "kubectl"
}

# Find the first cluster entry whose `hosts` matches the given host.
# `hosts` is either a regex string or a closure (host) -> bool.
# Returns the cluster record merged over CLUSTER_DEFAULTS. If none matches,
# returns just the defaults.
def cluster-for [host: string] {
  let clusters = kubebridge-config | get -o clusters | default []
  let matched = $clusters | where {|c|
    let h = $c | get -o hosts
    if ($h == null) { return false }
    let t = $h | describe
    if ($t | str starts-with "closure") {
      try { do $h $host } catch { false }
    } else if ($t == "string") {
      $host =~ $h
    } else {
      false
    }
  } | first
  $CLUSTER_DEFAULTS | merge ($matched | default {})
}

def kctl-prefix [cluster: record] {
  if $cluster.sudo { ["sudo" $cluster.kube_binary] } else { [$cluster.kube_binary] }
}

# ----------------------
#  Path layer
# ----------------------

def xdg-data-home [] {
  if ($env.XDG_DATA_HOME? | is-not-empty) { $env.XDG_DATA_HOME } else { [$env.HOME .local share] | path join }
}

def xdg-cache-home [] {
  if ($env.XDG_CACHE_HOME? | is-not-empty) { $env.XDG_CACHE_HOME } else { [$env.HOME .cache] | path join }
}

def state-file [] { [(xdg-data-home) nu-kube-bridge bridges.json] | path join }
def kubeconfigs-dir [] { [(xdg-cache-home) kube-bridge kubeconfigs] | path join }
def completion-cache-dir [] { [(xdg-cache-home) kube-bridge completions] | path join }

# SSH ControlMaster sockets must live under a *short* prefix: Unix-domain
# socket paths max at ~104 chars on macOS, and openssh appends a ~17-char
# atomic-create suffix while listening. So we keep these under /tmp instead
# of the long XDG paths. The state file still records the canonical socket
# path so cross-shell `kill`/`list` work.
def masters-dir [] { "/tmp/kb-masters" }
def completion-sockets-dir [] { "/tmp/kb-ssh-cm" }

def ensure-dir [p: string] {
  if not ($p | path exists) { mkdir $p }
}

# ----------------------
#  State CRUD
# ----------------------

def bridge-load [] {
  let p = state-file
  if ($p | path exists) { open $p } else { {} }
}

def bridge-save [state: record] {
  let p = state-file
  ensure-dir ($p | path dirname)
  $state | to json | save --force $p
}

def bridge-add [name: string, entry: record] {
  let state = bridge-load | upsert $name $entry
  bridge-save $state
}

def bridge-remove [name: string] {
  let state = bridge-load | reject -o $name
  bridge-save $state
}

# ----------------------
#  SSH master + forwards
# ----------------------

def master-socket [host: string] {
  [(masters-dir) $"($host).sock"] | path join
}

def master-alive [host: string] {
  let sock = master-socket $host
  if not ($sock | path exists) { return false }
  let r = (^ssh -O check -S $sock $host | complete)
  $r.exit_code == 0
}

def master-up [host: string] {
  if (master-alive $host) { return }
  let sock = master-socket $host
  ensure-dir ($sock | path dirname)
  if ($sock | path exists) { rm -f $sock }
  let r = (^ssh -fN -M -o ControlPersist=yes -S $sock $host | complete)
  if $r.exit_code != 0 {
    error make --unspanned {msg: $"could not start ssh master to ($host): ($r.stderr | str trim)"}
  }
}

def master-down [host: string] {
  let sock = master-socket $host
  if ($sock | path exists) {
    ^ssh -O exit -S $sock $host | complete | ignore
    if ($sock | path exists) { rm -f $sock }
  }
}

def forward-spec [bind: string, local_port: int, target_host: string, target_port: int] {
  $"($bind):($local_port):($target_host):($target_port)"
}

def forward-add [host: string, bind: string, local_port: int, target_host: string, target_port: int] {
  let sock = master-socket $host
  let spec = forward-spec $bind $local_port $target_host $target_port
  let r = (^ssh -O forward -L $spec -S $sock $host | complete)
  if $r.exit_code != 0 {
    error make --unspanned {msg: $"forward-add failed: ($r.stderr | str trim)"}
  }
}

def forward-cancel [host: string, bind: string, local_port: int, target_host: string, target_port: int] {
  let sock = master-socket $host
  if not ($sock | path exists) { return }
  let spec = forward-spec $bind $local_port $target_host $target_port
  ^ssh -O cancel -L $spec -S $sock $host | complete | ignore
}

# ----------------------
#  Completion cache + completers
# ----------------------

def completion-ttl-sec [] { 30 }
def completion-persist-sec [] { 60 }

def cache-path [...segments: string] {
  ([(completion-cache-dir) ...$segments] | path join)
}

def cache-fresh [p: string] {
  if not ($p | path exists) { return false }
  let mtime = (ls -l $p | get 0.modified)
  let age_ns = ((date now) - $mtime | into int)
  $age_ns < ((completion-ttl-sec) * 1_000_000_000)
}

def cache-read [p: string] {
  if (cache-fresh $p) { open $p } else { null }
}

def cache-write [p: string, data: any] {
  ensure-dir ($p | path dirname)
  $data | to json | save --force $p
}

def ssh-completion-args [] {
  let sockdir = completion-sockets-dir
  ensure-dir $sockdir
  let persist = completion-persist-sec
  let sockpath = [$sockdir "%C"] | path join
  [
    "-o" $"ControlMaster=auto"
    "-o" $"ControlPersist=($persist)s"
    "-o" $"ControlPath=($sockpath)"
  ]
}

def --wrapped kctl-completion [host: string, cluster: record, ...args: string] {
  let prefix = kctl-prefix $cluster
  let r = (^ssh ...(ssh-completion-args) $host ...$prefix ...$args | complete)
  if $r.exit_code != 0 { null } else { $r.stdout }
}

def default-list-namespaces [host: string, cluster: record] {
  let out = kctl-completion $host $cluster get ns -o "jsonpath={.items[*].metadata.name}"
  if ($out == null) { return [] }
  $out | str trim | split row ' ' | where ($it | str length) > 0
}

def default-list-services [host: string, ns: string, cluster: record] {
  let out = kctl-completion $host $cluster -n $ns get svc -o "jsonpath={.items[*].metadata.name}"
  if ($out == null) { return [] }
  $out | str trim | split row ' ' | where ($it | str length) > 0
}

def list-namespaces [host: string] {
  let cluster = cluster-for $host
  let custom = $cluster | get -o completion | default {} | get -o namespaces
  let p = cache-path $host "ns.json"
  let cached = cache-read $p
  if ($cached != null) { return $cached }
  let names = if ($custom != null) { do $custom $host } else { default-list-namespaces $host $cluster }
  cache-write $p $names
  $names
}

def list-services [host: string, ns: string] {
  let cluster = cluster-for $host
  let custom = $cluster | get -o completion | default {} | get -o services
  let p = cache-path $host $ns "svc.json"
  let cached = cache-read $p
  if ($cached != null) { return $cached }
  let names = if ($custom != null) { do $custom $host $ns } else { default-list-services $host $ns $cluster }
  cache-write $p $names
  $names
}

def default-host-list [] {
  let p = [$env.HOME ".ssh/known_hosts"] | path join
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

def host-completer [] {
  let cfg = kubebridge-config
  let custom = $cfg | get -o completion | default {} | get -o hosts
  if ($custom != null) { do $custom } else { default-host-list }
}

def active-name-completer [] { bridge-load | columns }

def ns-svc-completer [context: string] {
  let words = $context | split row ' ' | where ($it | str length) > 0
  if ($words | length) < 3 { return [] }
  let host = $words | get 2
  if ($host | str starts-with '--') { return [] }
  let partial = if ($context | str ends-with ' ') { "" } else { $words | last }
  if ($partial | str contains '/') {
    let parts = $partial | split row '/'
    let ns = $parts | get 0
    if ($ns | is-empty) { return [] }
    list-services $host $ns | each {|svc| $"($ns)/($svc)"}
  } else {
    list-namespaces $host | each {|ns| $"($ns)/"}
  }
}

# ----------------------
#  K8s discovery (live, via host master)
# ----------------------

def resolve-service [host: string, ns: string, svc: string, target_port: any, cluster: record] {
  let sock = master-socket $host
  let prefix = kctl-prefix $cluster
  let r = (^ssh -S $sock $host ...$prefix -n $ns get svc $svc -o json | complete)
  if $r.exit_code != 0 {
    error make --unspanned {msg: $"kubectl get svc failed: ($r.stderr | str trim)"}
  }
  let parsed = $r.stdout | from json
  let clusterip = $parsed.spec.clusterIP
  let ports = $parsed.spec.ports
  let available = $ports | get port | each {|p| $p | into string} | str join ", "
  let chosen = if ($target_port != null) {
    let m = $ports | where port == $target_port
    if ($m | is-empty) {
      error make --unspanned {msg: $"port ($target_port) not found on service ($ns)/($svc); available: ($available)"}
    }
    $m | first
  } else if (($ports | length) > 1) {
    error make --unspanned {msg: $"service ($ns)/($svc) exposes multiple ports \(($available)\); pass --target-port"}
  } else {
    $ports | first
  }
  { clusterip: $clusterip, target_port: $chosen.port }
}

# ----------------------
#  Kubeconfig helper
# ----------------------

# Fetch the remote kubeconfig to a local path. When `sudo` is true, route
# through `ssh host sudo cat <path>` so kubeadm's root-only admin.conf is
# readable. Otherwise use scp over the existing master.
def fetch-remote-kubeconfig [host: string, remote_path: string, local_path: string, use_sudo: bool] {
  if $use_sudo {
    let sock = master-socket $host
    let r = (^ssh -S $sock $host sudo -n cat $remote_path | complete)
    if $r.exit_code != 0 {
      error make --unspanned {msg: $"sudo cat ($remote_path) failed: ($r.stderr | str trim)"}
    }
    $r.stdout | save --force $local_path
  } else {
    ^scp -o $"ControlPath=(master-socket $host)" $"($host):($remote_path)" $local_path
  }
}

def kubeconfig-set-server [file: string, local_port: int] {
  open $file
  | update clusters {|doc|
      $doc.clusters | each {|c|
        let orig = $c.cluster.server
        let orig_host = $orig | parse --regex '^https?://(?P<h>[^:/]+)' | get -o h.0 | default "127.0.0.1"
        $c
        | update cluster.server $"https://127.0.0.1:($local_port)"
        | upsert cluster.tls-server-name $orig_host
      }
    }
  | to yaml
  | save --force $file
}

# ----------------------
#  Hooks
# ----------------------

def run-hooks [key: string, entry: record] {
  let hooks = kubebridge-config | get -o hooks | default {} | get -o $key | default []
  $hooks | each {|h| try { do $h $entry } } | ignore
}

# ----------------------
#  Public commands
# ----------------------

# List active bridges with their liveness status.
#
# Reads the cross-shell state file and augments every recorded bridge with a
# live `status` column — `alive` or `dead` — probed via `ssh -O check` against
# that host's ControlMaster socket. Because both the state file and the sockets
# live outside any single shell, this reflects every bridge opened from any
# shell, not just the current one. Returns an empty list when nothing is bridged.
@category kubernetes
@search-terms bridge tunnel forward list status ssh kubernetes
@example "every bridge, with liveness" { kube-bridge list } --result [{kind: "apiserver", host: "k8s-01", bind_address: "127.0.0.1", local_port: 6443, target_host: "127.0.0.1", target_port: 6443, master_sock: "/tmp/kb-masters/k8s-01.sock", kubeconfig: "~/.cache/kube-bridge/kubeconfigs/apiserver-k8s-01.yaml", name: "apiserver-k8s-01", status: "alive"}]
@example "only the live ones" { kube-bridge list | where status == alive }
@example "the local ports currently in use" { kube-bridge list | select name local_port }
export def list []: nothing -> table {
  let state = bridge-load
  $state
  | transpose name entry
  | each {|row|
      $row.entry
      | insert name $row.name
      | insert status (if (master-alive $row.entry.host) { "alive" } else { "dead" })
    }
}

# Kill a bridge by name. Returns the killed entry.
#
# Cancels the port-forward for this bridge's exact `-L` spec via `ssh -O cancel`,
# removes it from the state file, and — if it was the last bridge on its host —
# shuts that host's ControlMaster down with `ssh -O exit`. For an `apiserver`
# bridge it also deletes the patched kubeconfig and, when the current
# `$env.KUBECONFIG` pointed at it, unsets that variable (hence `--env`).
# Registered `on_close` hooks run first, each receiving the entry. Errors if no
# active bridge has that name — tab-complete the name to avoid typos.
@category kubernetes
@search-terms kill stop close teardown bridge tunnel forward
@example "tear a bridge down from any shell" { kube-bridge kill apiserver-k8s-01 } --result {kind: "apiserver", host: "k8s-01", local_port: 6443, name: "apiserver-k8s-01", kubeconfig: "~/.cache/kube-bridge/kubeconfigs/apiserver-k8s-01.yaml"}
export def --env kill [
  name: string@active-name-completer  # name of an active bridge (tab-completes)
]: nothing -> record {
  let state = bridge-load
  let entry = $state | get -o $name
  if ($entry == null) {
    error make --unspanned {msg: $"no active bridge named '($name)'"}
  }
  let full_entry = $entry | insert name $name
  run-hooks "on_close" $full_entry
  let bind = $entry | get -o bind_address | default "127.0.0.1"
  forward-cancel $entry.host $bind $entry.local_port $entry.target_host $entry.target_port
  bridge-remove $name
  let remaining = bridge-load | values | where host == $entry.host
  if ($remaining | is-empty) { master-down $entry.host }
  if $entry.kind == "apiserver" {
    let kc = $entry | get -o kubeconfig | default ""
    if ($kc | is-not-empty) {
      if ($kc | path exists) { rm -f $kc }
      if (($env.KUBECONFIG? | default "") == $kc) { hide-env KUBECONFIG }
    }
  }
  $full_entry
}

# Kill every active bridge. Returns the list of killed entries.
#
# Iterates `kill` over every bridge in the state file, tearing down forwards,
# host masters, and apiserver kubeconfigs as it goes. `--env` because the
# underlying `kill` may unset `$env.KUBECONFIG`. Returns `[]` when nothing was
# bridged.
@category kubernetes
@search-terms kill-all stop close teardown all bridges reset cleanup
@example "tear everything down" { kube-bridge kill-all }
export def --env kill-all []: nothing -> table {
  let names = bridge-load | columns
  mut killed = []
  for name in $names {
    $killed = ($killed | append (kill $name))
  }
  $killed
}

# Open a tunnel to the kube-apiserver on a remote host and point KUBECONFIG at it.
#
# Brings up (or reuses) the host's SSH ControlMaster, fetches the remote
# kubeconfig — via `scp`, or `ssh sudo -n cat` when the matched cluster is
# `sudo: true` — and rewrites it so `cluster.server` becomes
# `https://127.0.0.1:<local-port>` while `tls-server-name` is pinned to the
# original hostname (so the apiserver's TLS SAN still verifies over loopback).
# It then forwards `<bind-address>:<local-port>` to the remote apiserver, records
# the bridge in the cross-shell state file, sets `$env.KUBECONFIG` in the calling
# shell (hence `--env`), and runs any `on_open` hooks. Per-cluster paths, ports,
# and sudo come from `$env.kubebridge_config`; the flags override them per call.
# Returns the new bridge entry.
@category kubernetes
@search-terms apiserver kubeconfig tunnel bridge forward ssh cluster kubectl
@example "bridge a cluster's apiserver, then use kubectl through it" {
  kube-bridge apiserver k8s-01
  kubectl get nodes
}
@example "pin the local port and name the bridge" { kube-bridge apiserver k8s-01 --port 6443 --name prod }
@example "share the tunnel with local VMs / containers" { kube-bridge apiserver k8s-01 --bind-address 0.0.0.0 }
export def --env apiserver [
  host: string@host-completer            # ssh target (tab-completes from config / known_hosts)
  --name: string                         # bridge name; defaults to "apiserver-<host>"
  --port: int                            # local port; defaults to a free port near 6443
  --remote-kubeconfig: string            # kubeconfig path on the remote; overrides the cluster's value
  --remote-port: int                     # remote apiserver port; overrides the cluster's value
  --bind-address: string = "127.0.0.1"   # local bind address for the forward (0.0.0.0 to share)
]: nothing -> record {
  let cluster = cluster-for $host
  let remote_kc = $remote_kubeconfig | default $cluster.remote_kubeconfig
  let remote_p  = $remote_port       | default $cluster.remote_apiserver_port

  let bridge_name = $name | default $"apiserver-($host)"
  let local_port = if ($port == null) { port } else { $port }

  master-up $host

  let kc_dir = kubeconfigs-dir
  ensure-dir $kc_dir
  let kc_path = [$kc_dir $"($bridge_name).yaml"] | path join

  fetch-remote-kubeconfig $host $remote_kc $kc_path $cluster.sudo
  kubeconfig-set-server $kc_path $local_port

  forward-add $host $bind_address $local_port "127.0.0.1" $remote_p

  let entry = {
    kind: "apiserver"
    host: $host
    bind_address: $bind_address
    local_port: $local_port
    target_host: "127.0.0.1"
    target_port: $remote_p
    master_sock: (master-socket $host)
    kubeconfig: $kc_path
  }
  bridge-add $bridge_name $entry

  $env.KUBECONFIG = $kc_path
  let full_entry = $entry | insert name $bridge_name
  run-hooks "on_open" $full_entry
  $full_entry
}

# Open a tunnel to a k8s service on a remote host. Returns the new bridge entry.
#
# Brings up (or reuses) the host's SSH ControlMaster, resolves the service's
# ClusterIP and port live with `kubectl get svc -o json` over that master, then
# forwards `<bind-address>:<local-port>` straight to `ClusterIP:port`. When the
# service exposes several ports you must disambiguate with `--target-port`. The
# bridge is recorded in the cross-shell state file and `on_open` hooks run.
# Unlike `apiserver`, this sets no `$env.KUBECONFIG`. Returns the new entry.
@category kubernetes
@search-terms service svc tunnel bridge forward clusterip port ssh kubectl
@example "forward coredns to a local port" { kube-bridge service k8s-01 kube-system/coredns } --result {kind: "service", host: "k8s-01", bind_address: "127.0.0.1", local_port: 53, target_host: "10.96.0.10", target_port: 53, master_sock: "/tmp/kb-masters/k8s-01.sock", ns: "kube-system", svc: "coredns", name: "coredns-k8s-01"}
@example "pick the port on a multi-port service" { kube-bridge service k8s-01 default/argocd-server --target-port 443 }
@example "fixed local port and a custom name" { kube-bridge service k8s-01 media/jellyfin --port 8096 --name jelly }
export def service [
  host: string@host-completer            # ssh target (tab-completes from config / known_hosts)
  target: string@ns-svc-completer        # <namespace>/<service> (both parts tab-complete)
  --name: string                         # bridge name; defaults to "<svc>-<host>"
  --port: int                            # local port; defaults to a free port near the target port
  --target-port: int                     # remote service port (required when the service exposes several)
  --bind-address: string = "127.0.0.1"   # local bind address for the forward (0.0.0.0 to share)
]: nothing -> record {
  let parts = $target | split row '/'
  if ($parts | length) != 2 {
    error make --unspanned {msg: $"target must be in <namespace>/<service> form; got '($target)'"}
  }
  let ns = $parts | get 0
  let svc = $parts | get 1
  if ($ns | is-empty) or ($svc | is-empty) {
    error make --unspanned {msg: $"target must be in <namespace>/<service> form; got '($target)'"}
  }

  let cluster = cluster-for $host
  master-up $host

  let resolved = resolve-service $host $ns $svc $target_port $cluster
  let bridge_name = $name | default $"($svc)-($host)"
  let local_port = if ($port == null) { port $resolved.target_port } else { $port }

  forward-add $host $bind_address $local_port $resolved.clusterip $resolved.target_port

  let entry = {
    kind: "service"
    host: $host
    bind_address: $bind_address
    local_port: $local_port
    target_host: $resolved.clusterip
    target_port: $resolved.target_port
    master_sock: (master-socket $host)
    ns: $ns
    svc: $svc
  }
  bridge-add $bridge_name $entry

  let full_entry = $entry | insert name $bridge_name
  run-hooks "on_open" $full_entry
  $full_entry
}
