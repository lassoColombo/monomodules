# kube-bridge

SSH-tunnel a remote Kubernetes apiserver or service to a local port, and manage
every tunnel from any shell.

Bridges are backed by one SSH `ControlMaster` per host and a JSON state file, so
`list` and `kill` work across shells — and returned as **structured, typed
data**, never a pre-formatted string.

---

- [Why?](#why)
- [Installation](#installation)
  - [Requirements](#requirements)
- [Quick start](#quick-start)
- [Two kinds of bridge](#two-kinds-of-bridge)
- [Configuration](#configuration)
  - [Matching a host to a cluster](#matching-a-host-to-a-cluster)
  - [Cluster fields](#cluster-fields)
  - [Completion overrides](#completion-overrides)
  - [Hooks](#hooks)
- [How it works](#how-it-works)
  - [One SSH ControlMaster per host](#one-ssh-controlmaster-per-host)
  - [Kubeconfig patching (apiserver only)](#kubeconfig-patching-apiserver-only)
  - [Completion](#completion)
  - [Paths](#paths)
- [Commands](#commands)
  - [`kube-bridge apiserver`](#kube-bridge-apiserver)
  - [`kube-bridge kill`](#kube-bridge-kill)
  - [`kube-bridge kill-all`](#kube-bridge-kill-all)
  - [`kube-bridge list`](#kube-bridge-list)
  - [`kube-bridge service`](#kube-bridge-service)
- [Recipes](#recipes)
- [Pitfalls](#pitfalls)
- [Mentions](#mentions)

## Why?

`ssh -L 6443:127.0.0.1:6443 host` works fine until you want a second tunnel, or
want to know which ones are live, or want to kill one from a shell other than the
one that opened it.

`kube-bridge` answers the questions that `ssh -L` and `kubectl port-forward`
leave awkward:

- *how do I reach a homelab cluster's apiserver from my laptop without exposing
  6443 to the network?*
- *how do I hold tunnels to two clusters at once, each on its own local port?*
- *how do I hit a bare `ClusterIP` service (a DB, a dashboard, Argo CD) that has
  no Ingress or NodePort — and have the tunnel outlive the shell that opened it?*
- *which bridges are open right now, and are their masters still alive?*
- *how do I tear one down from a different shell?*

It keeps one SSH `ControlMaster` per host as a normal detached OS process and
records its socket path in a JSON file under `$XDG_DATA_HOME`. Every shell can
see and manage every bridge:

```nu
use kube-bridge

kube-bridge apiserver k8s-node-01          # open a tunnel, set $env.KUBECONFIG
kubectl get pods -n media                  # …works through the tunnel
kube-bridge list                           # see every bridge from any shell
kube-bridge kill apiserver-k8s-node-01     # tear it down from any shell
```

Every command **returns a structured value and prints nothing**, so you filter,
select, and pipe the result like any other Nushell data:

```nu
kube-bridge list | where status == dead | get name | each { kube-bridge kill $in }
```

It also handles the parts that aren't obvious the first time — root-only
`admin.conf`, loopback TLS verification, fast completion — see
[How it works](#how-it-works).

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) kube-bridge] | path join
git clone git@github.com:lassoColombo/kube-bridge.git $dest

# in config.nu
use kube-bridge
kube-bridge apiserver --help
```

### Requirements

- **Nushell 0.114+** (return-type signatures, `def --env`, list completions).
- `ssh` and `scp` on the local machine, with the master feature available
  (default OpenSSH).
- `kubectl` (or an equivalent, per `kube_binary`) on the **remote** host — it is
  run over SSH to resolve services and, for `apiserver`, is never needed locally.
- Optionally passwordless `sudo` on the remote when the kubeconfig is root-only
  (kubeadm's `admin.conf`) — set `sudo: true` on the cluster.

SSH options like jump hosts, identity files, and usernames are **not** part of
this module's config — keep them in `~/.ssh/config`, where they belong.

## Quick start

```nu
use kube-bridge

# apiserver bridge — patches a kubeconfig, sets $env.KUBECONFIG
kube-bridge apiserver my-host
kubectl get nodes

# service bridge — resolves ClusterIP + port live via `kubectl get svc`
kube-bridge service my-host kube-system/coredns
nc -z localhost <local-port>

# see everything, from any shell
kube-bridge list

# tear down — by name, or all at once
kube-bridge kill coredns-my-host
kube-bridge kill-all
```

Both openers return the bridge entry:

```nu
kube-bridge apiserver my-host
# => {
#   kind: apiserver, host: my-host, bind_address: 127.0.0.1, local_port: 60473,
#   target_host: 127.0.0.1, target_port: 6443,
#   master_sock: /tmp/kb-masters/my-host.sock,
#   kubeconfig: ~/.cache/kube-bridge/kubeconfigs/apiserver-my-host.yaml,
#   name: apiserver-my-host
# }
```

## Two kinds of bridge

There is one command per kind; both forward a local port over the host's SSH
master, and both are torn down the same way (`kill` / `kill-all`).

| | `apiserver` | `service` |
|---|---|---|
| **Forwards to** | the remote's kube-apiserver (`127.0.0.1:6443` on the host) | a service's live `ClusterIP:port` inside the cluster |
| **Target syntax** | just `<host>` | `<host> <namespace>/<service>` |
| **Sets `$env.KUBECONFIG`** | yes — to a patched copy of the remote kubeconfig | no |
| **Needs the remote kubeconfig** | yes (fetched + patched) | no |
| **Default local port** | free port near `6443` | free port near the service's port |
| **Use it to** | run `kubectl` against a remote cluster over SSH | reach a bare `ClusterIP` (DB, dashboard, Argo CD…) with no Ingress |

## Configuration

Everything lives in `$env.kubebridge_config`. Nothing in the module is hardcoded
for any specific cluster — an empty config is valid and every field falls back to
a built-in default.

```nu
$env.kubebridge_config = {
  # Optional. Overrides for the argument completers. Each is a closure.
  completion: {
    hosts: { || open ~/.ssh/known_hosts | lines | ... }   # <host> suggestions
  }

  # Optional. Closures run after open / before close; each gets the bridge entry.
  hooks: {
    on_open:  [{ |entry| print $"opened ($entry.name) on ($entry.local_port)" }]
    on_close: [{ |entry| ... }]
  }

  # Clusters are matched in order; first match wins. Any omitted field falls back
  # to the defaults: /etc/kubernetes/admin.conf, 6443, sudo:false, kubectl.
  clusters: [
    {
      hosts: "dmilog"                                 # regex against the host arg
      remote_kubeconfig: "/etc/rancher/k3s/k3s.yaml"
      remote_apiserver_port: 6443
    }
    {
      hosts: { |h| $h | str ends-with ".example.com" } # or a closure (host) -> bool
      remote_kubeconfig: "/etc/kubernetes/admin.conf"
      sudo: true                                       # fetch admin.conf via ssh sudo -n cat
      kube_binary: "kubectl"                           # or "k3s kubectl", "microk8s kubectl", …
      completion: {
        namespaces: { |host| ["default" "kube-system" "media"] }
        services:   { |host, ns| [] }
      }
    }
  ]
}
```

### Matching a host to a cluster

When you run `apiserver <host>` or `service <host> …`, the host is matched
against each entry in `clusters` **in order**, and the first match wins. A
cluster's `hosts` field is either:

- a **regex string** — matched with `=~` against the host argument, or
- a **closure** `{ |host| … } -> bool` — for arbitrary logic (suffix, list
  membership, a lookup).

The matched cluster is merged over the defaults, so you only specify what
differs. If nothing matches, the defaults are used as-is — which is exactly right
for a stock kubeadm cluster reachable as its own SSH host.

### Cluster fields

| Field | Default | Meaning |
|---|---|---|
| `hosts` | — | Regex string or `(host) -> bool` closure that selects this cluster. |
| `remote_kubeconfig` | `/etc/kubernetes/admin.conf` | Path to the kubeconfig **on the remote**, fetched by `apiserver`. |
| `remote_apiserver_port` | `6443` | Port the apiserver listens on, on the remote. |
| `sudo` | `false` | When `true`, read the kubeconfig via `ssh host sudo -n cat` and prefix remote `kubectl` with `sudo`. |
| `kube_binary` | `"kubectl"` | The remote kubectl invocation, e.g. `"k3s kubectl"`, `"microk8s kubectl"`. |
| `completion` | — | Per-cluster completer overrides — see below. |

Per-call flags (`--remote-kubeconfig`, `--remote-port`) override the matched
cluster's values for that one invocation.

### Completion overrides

By default the `<namespace>/<service>` argument is completed by running
`kubectl get ns` / `get svc` on the remote over a fast, cached SSH pool. Override
either lookup per cluster when that's too slow, needs different flags, or you'd
rather hardcode a short list:

```nu
completion: {
  namespaces: { |host| ["default" "kube-system" "media"] }
  services:   { |host, ns| kubectl-somehow $host $ns }
}
```

The top-level `completion.hosts` closure (not per-cluster) supplies suggestions
for the `<host>` argument itself; it defaults to the entries in
`~/.ssh/known_hosts`.

### Hooks

`hooks.on_open` runs after a bridge is opened, `hooks.on_close` just before one
is killed. Each is a **list of closures**, each receiving the bridge entry
(including its `name`). Use them to update `/etc/hosts`, send a notification,
warm a cache, etc.

```nu
hooks: {
  on_open:  [{ |e| $"($e.host) → 127.0.0.1:($e.local_port)" | save --append ~/bridges.log }]
  on_close: [{ |e| print $"closing ($e.name)" }]
}
```

Hooks run inside `try`, so a misbehaving closure can't break the bridge — but it
also can't abort the action by throwing. Surface failures inside the hook itself.

## How it works

### One SSH ControlMaster per host

`apiserver` and `service` run `ssh -fN -M -o ControlPersist=yes -S <sock> <host>`
once per host, then add forwards via
`ssh -O forward -L <bind>:<lport>:<thost>:<tport> -S <sock> <host>`. Killing a
bridge calls `ssh -O cancel …` for that exact `-L` spec; killing the last bridge
on a host calls `ssh -O exit …`.

Because the master is a normal OS process, any shell can manage it through the
socket file. The state file is just a `{ <name>: <entry> }` record keyed by
bridge name, so `list` and `kill` don't care which shell opened what.

### Kubeconfig patching (apiserver only)

After fetching the remote kubeconfig, every `clusters[].cluster.server` is
rewritten to `https://127.0.0.1:<local-port>`, and
`clusters[].cluster.tls-server-name` is pinned to the **original** hostname so
the cert's SAN list still matches. This is the trick that makes a kubeadm cluster
(whose cert is signed for the LAN IP, not loopback) verify over a localhost
forward: the TCP connection goes to `127.0.0.1:<local-port>`, but SNI/verification
uses the original name.

When the cluster is `sudo: true`, the root-only `admin.conf` is read via
`ssh host sudo -n cat <path>`; otherwise it's copied with `scp` over the existing
master.

### Completion

The `<host>` argument is completed from `completion.hosts` (closure) or
`~/.ssh/known_hosts`. The `<namespace>/<service>` argument looks up the cluster
for the typed host, then calls that cluster's `completion.namespaces` /
`completion.services` closures or the built-in `ssh host kubectl get ns/svc`
path. Results are cached on disk for 30s and the SSH connection is kept warm by a
**separate** `ControlMaster=auto` pool with `ControlPersist=60s` — completion
never touches the long-lived bridge masters, so it stays fast and can't disturb a
live tunnel. When the host is unreachable, completion simply offers nothing.

### Paths

| Purpose | Path |
|---|---|
| State file | `~/.local/share/nu-kube-bridge/bridges.json` |
| Patched kubeconfigs | `~/.cache/kube-bridge/kubeconfigs/<name>.yaml` |
| Bridge ControlMaster sockets | `/tmp/kb-masters/<host>.sock` |
| Completion ControlMaster sockets | `/tmp/kb-ssh-cm/%C` |
| Completion cache | `~/.cache/kube-bridge/completions/` |

Sockets live under `/tmp`, not the XDG dirs, on purpose: a Unix-domain socket
path maxes out at ~104 chars on macOS and OpenSSH appends a ~17-char atomic-create
suffix while listening, so the long XDG paths overflow on most usernames.

<!-- BEGIN GENERATED COMMANDS -->
## Commands

| Command                                           | Signature           | Description                                                                      |
| ------------------------------------------------- | ------------------- | -------------------------------------------------------------------------------- |
| [`kube-bridge apiserver`](#kube-bridge-apiserver) | `nothing -> record` | Open a tunnel to the kube-apiserver on a remote host and point KUBECONFIG at it. |
| [`kube-bridge kill`](#kube-bridge-kill)           | `nothing -> record` | Kill a bridge by name.                                                           |
| [`kube-bridge kill-all`](#kube-bridge-kill-all)   | `nothing -> table`  | Kill every active bridge.                                                        |
| [`kube-bridge list`](#kube-bridge-list)           | `nothing -> table`  | List active bridges with their liveness status.                                  |
| [`kube-bridge service`](#kube-bridge-service)     | `nothing -> record` | Open a tunnel to a k8s service on a remote host.                                 |

### `kube-bridge apiserver`

Open a tunnel to the kube-apiserver on a remote host and point KUBECONFIG at it.

Brings up (or reuses) the host's SSH ControlMaster, fetches the remote  
kubeconfig — via `scp`, or `ssh sudo -n cat` when the matched cluster is  
`sudo: true` — and rewrites it so `cluster.server` becomes  
`https://127.0.0.1:<local-port>` while `tls-server-name` is pinned to the  
original hostname (so the apiserver's TLS SAN still verifies over loopback).  
It then forwards `<bind-address>:<local-port>` to the remote apiserver, records  
the bridge in the cross-shell state file, sets `$env.KUBECONFIG` in the calling  
shell (hence `--env`), and runs any `on_open` hooks. Per-cluster paths, ports,  
and sudo come from `$env.kubebridge_config`; the flags override them per call.  
Returns the new bridge entry.

**Signature:** `nothing -> record` · **Category:** `kubernetes`

**Parameters**

| Parameter | Type     | Description                                          |
| --------- | -------- | ---------------------------------------------------- |
| `host`    | `string` | ssh target (tab-completes from config / known_hosts) |

**Flags**

| Flag                  | Type     | Default       | Description                                                  |
| --------------------- | -------- | ------------- | ------------------------------------------------------------ |
| `--name`              | `string` |               | bridge name; defaults to "apiserver-<host>"                  |
| `--port`              | `int`    |               | local port; defaults to a free port near 6443                |
| `--remote-kubeconfig` | `string` |               | kubeconfig path on the remote; overrides the cluster's value |
| `--remote-port`       | `int`    |               | remote apiserver port; overrides the cluster's value         |
| `--bind-address`      | `string` | `"127.0.0.1"` | local bind address for the forward (0.0.0.0 to share)        |

**Search terms:** `apiserver`, `kubeconfig`, `tunnel`, `bridge`, `forward`, `ssh`, `cluster`, `kubectl`

**Examples**

```nu
# bridge a cluster's apiserver, then use kubectl through it
kube-bridge apiserver k8s-01
kubectl get nodes

# pin the local port and name the bridge
kube-bridge apiserver k8s-01 --port 6443 --name prod

# share the tunnel with local VMs / containers
kube-bridge apiserver k8s-01 --bind-address 0.0.0.0
```

### `kube-bridge kill`

Kill a bridge by name. Returns the killed entry.

Cancels the port-forward for this bridge's exact `-L` spec via `ssh -O cancel`,  
removes it from the state file, and — if it was the last bridge on its host —  
shuts that host's ControlMaster down with `ssh -O exit`. For an `apiserver`  
bridge it also deletes the patched kubeconfig and, when the current  
`$env.KUBECONFIG` pointed at it, unsets that variable (hence `--env`).  
Registered `on_close` hooks run first, each receiving the entry. Errors if no  
active bridge has that name — tab-complete the name to avoid typos.

**Signature:** `nothing -> record` · **Category:** `kubernetes`

**Parameters**

| Parameter | Type     | Description                              |
| --------- | -------- | ---------------------------------------- |
| `name`    | `string` | name of an active bridge (tab-completes) |

**Search terms:** `kill`, `stop`, `close`, `teardown`, `bridge`, `tunnel`, `forward`

**Examples**

```nu
# tear a bridge down from any shell
kube-bridge kill apiserver-k8s-01
# => {kind: apiserver, host: "k8s-01", local_port: 6443, name: "apiserver-k8s-01", kubeconfig: "~/.cache/kube-bridge/kubeconfigs/apiserver-k8s-01.yaml"}
```

### `kube-bridge kill-all`

Kill every active bridge. Returns the list of killed entries.

Iterates `kill` over every bridge in the state file, tearing down forwards,  
host masters, and apiserver kubeconfigs as it goes. `--env` because the  
underlying `kill` may unset `$env.KUBECONFIG`. Returns `[]` when nothing was  
bridged.

**Signature:** `nothing -> table` · **Category:** `kubernetes`

**Search terms:** `kill-all`, `stop`, `close`, `teardown`, `all`, `bridges`, `reset`, `cleanup`

**Examples**

```nu
# tear everything down
kube-bridge kill-all
```

### `kube-bridge list`

List active bridges with their liveness status.

Reads the cross-shell state file and augments every recorded bridge with a  
live `status` column — `alive` or `dead` — probed via `ssh -O check` against  
that host's ControlMaster socket. Because both the state file and the sockets  
live outside any single shell, this reflects every bridge opened from any  
shell, not just the current one. Returns an empty list when nothing is bridged.

**Signature:** `nothing -> table` · **Category:** `kubernetes`

**Search terms:** `bridge`, `tunnel`, `forward`, `list`, `status`, `ssh`, `kubernetes`

**Examples**

```nu
# every bridge, with liveness
kube-bridge list
# => [[kind, host, bind_address, local_port, target_host, target_port, master_sock, kubeconfig, name, status]; [apiserver, "k8s-01", "127.0.0.1", 6443, "127.0.0.1", 6443, "/tmp/kb-masters/k8s-01.sock", "~/.cache/kube-bridge/kubeconfigs/apiserver-k8s-01.yaml", "apiserver-k8s-01", alive]]

# only the live ones
kube-bridge list | where status == alive

# the local ports currently in use
kube-bridge list | select name local_port
```

### `kube-bridge service`

Open a tunnel to a k8s service on a remote host. Returns the new bridge entry.

Brings up (or reuses) the host's SSH ControlMaster, resolves the service's  
ClusterIP and port live with `kubectl get svc -o json` over that master, then  
forwards `<bind-address>:<local-port>` straight to `ClusterIP:port`. When the  
service exposes several ports you must disambiguate with `--target-port`. The  
bridge is recorded in the cross-shell state file and `on_open` hooks run.  
Unlike `apiserver`, this sets no `$env.KUBECONFIG`. Returns the new entry.

**Signature:** `nothing -> record` · **Category:** `kubernetes`

**Parameters**

| Parameter | Type     | Description                                          |
| --------- | -------- | ---------------------------------------------------- |
| `host`    | `string` | ssh target (tab-completes from config / known_hosts) |
| `target`  | `string` | <namespace>/<service> (both parts tab-complete)      |

**Flags**

| Flag             | Type     | Default       | Description                                                     |
| ---------------- | -------- | ------------- | --------------------------------------------------------------- |
| `--name`         | `string` |               | bridge name; defaults to "<svc>-<host>"                         |
| `--port`         | `int`    |               | local port; defaults to a free port near the target port        |
| `--target-port`  | `int`    |               | remote service port (required when the service exposes several) |
| `--bind-address` | `string` | `"127.0.0.1"` | local bind address for the forward (0.0.0.0 to share)           |

**Search terms:** `service`, `svc`, `tunnel`, `bridge`, `forward`, `clusterip`, `port`, `ssh`, `kubectl`

**Examples**

```nu
# forward coredns to a local port
kube-bridge service k8s-01 kube-system/coredns
# => {kind: service, host: "k8s-01", bind_address: "127.0.0.1", local_port: 53, target_host: "10.96.0.10", target_port: 53, master_sock: "/tmp/kb-masters/k8s-01.sock", ns: kube-system, svc: coredns, name: "coredns-k8s-01"}

# pick the port on a multi-port service
kube-bridge service k8s-01 default/argocd-server --target-port 443

# fixed local port and a custom name
kube-bridge service k8s-01 media/jellyfin --port 8096 --name jelly
```
<!-- END GENERATED COMMANDS -->

## Recipes

```nu
# open an apiserver bridge and immediately work against it
kube-bridge apiserver k8s-01
kubectl get nodes
kubectl get pods -A

# hold two clusters at once — each gets its own local port and KUBECONFIG file
kube-bridge apiserver prod-01  --name prod
kube-bridge apiserver stage-01 --name stage
kube-bridge list | select name host local_port

# point *another* shell at an apiserver bridge without reopening it
$env.KUBECONFIG = (kube-bridge list | where name == apiserver-k8s-01 | get 0.kubeconfig)

# reach a bare ClusterIP service and curl it
let b = kube-bridge service k8s-01 monitoring/grafana
http get $"http://127.0.0.1:($b.local_port)/api/health"

# garbage-collect dead bridges
kube-bridge list | where status == dead | get name | each { kube-bridge kill $in }

# share a bridge with local VMs / containers, then tear everything down on logout
kube-bridge apiserver k8s-01 --bind-address 0.0.0.0
# …later…
kube-bridge kill-all
```

## Pitfalls

- **Passwordless `sudo -n`** is assumed when a cluster is `sudo: true`. If the
  host prompts for a password, the kubeconfig fetch fails immediately rather than
  hanging.
- **`ssh -O cancel` matches the exact `-L` spec**, bind address included.
  `kube-bridge` records `bind_address` in the state so kills work from any shell;
  if you hand-edit the state file, keep that field intact.
- **`$env.KUBECONFIG` is not propagated across shells.** The shell that opened an
  `apiserver` bridge gets it set; other shells point at the persisted kubeconfig
  path themselves (see the recipe) or open their own bridge — the second open is
  a no-op against the existing master.
- **Hooks run in `try` blocks.** They can't break a bridge, but they can't abort
  the action by throwing either — surface failures inside the hook.

## Mentions

- Commands section generated with
  [`readme-commands-section-generator`](../readme-commands-section-generator).
