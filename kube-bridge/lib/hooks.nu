# kube-bridge/lib/hooks — the one thing that still lives in the environment.
#
# `$env.kubebridge_config` carries CLOSURES only: the completers you swap in for
# the built-in ones, and the callbacks run around a bridge's life. Everything
# data-shaped — the clusters — is read from clusters.yaml instead (lib/config.nu),
# because a closure cannot survive a round-trip through YAML and a cluster record
# has no business being written in Nushell source.
#
#   $env.kubebridge_config = {
#     completion: { hosts: {|| … }, namespaces: {|host| … }, services: {|host, ns| … } }
#     hooks: { on_open: [{|entry| … }], on_close: [{|entry| … }] }
#   }

def settings [] {
  $env.kubebridge_config? | default {}
}

# The user's override closure for a completer, or null when they set none.
export def "completion" [name: string]: nothing -> any {
  settings | get -o completion | default {} | get -o $name
}

# Run every closure registered under `hooks.<key>`, handing it the bridge entry.
# Each runs inside `try`: a misbehaving hook can neither break a bridge nor abort
# the action by throwing, so a hook that wants to be heard must say so itself.
def fire [key: string, entry: record] {
  settings | get -o hooks | default {} | get -o $key | default []
  | each {|h| try { do $h $entry } }
  | ignore
}

# The two lifecycle events, fired once a bridge is up and just before one dies.
export def "on-open" [entry: record] { fire "on_open" $entry }
export def "on-close" [entry: record] { fire "on_close" $entry }
