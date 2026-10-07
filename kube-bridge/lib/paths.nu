# kube-bridge/lib/paths — every path the module touches, in one place.
# Import individually: `use ./lib/paths.nu` → `paths clusters-file`, `paths state-file`, …
#
# Durable state and the config file follow the XDG base dirs. ControlMaster
# SOCKETS deliberately do not: a Unix-domain socket path maxes out at ~104 chars
# on macOS and OpenSSH appends a ~17-char atomic-create suffix while listening,
# so a long XDG path overflows. Those live under /tmp — don't move them back.

def xdg [var: string, fallback: string] {
  let set = $env | get -o $var | default ""
  if ($set | is-not-empty) { $set } else { [$nu.home-dir $fallback] | path join }
}

export def "config-home" []: nothing -> string { xdg XDG_CONFIG_HOME .config }
export def "data-home" []: nothing -> string { xdg XDG_DATA_HOME ".local/share" }
export def "cache-home" []: nothing -> string { xdg XDG_CACHE_HOME .cache }

# Where the user's own configuration lives, and the file inside it.
export def "config-dir" []: nothing -> string { [(config-home) kube-bridge] | path join }
export def "clusters-file" []: nothing -> string { [(config-dir) clusters.yaml] | path join }

# The cross-shell bridge state, and the per-bridge patched kubeconfigs.
export def "state-file" []: nothing -> string { [(data-home) nu-kube-bridge bridges.json] | path join }
export def "kubeconfigs-dir" []: nothing -> string { [(cache-home) kube-bridge kubeconfigs] | path join }
export def "completion-cache-dir" []: nothing -> string { [(cache-home) kube-bridge completions] | path join }

# Short-prefix socket dirs (see the note at the top of this file).
export def "masters-dir" []: nothing -> string { "/tmp/kb-masters" }
export def "completion-sockets-dir" []: nothing -> string { "/tmp/kb-ssh-cm" }

export def "ensure-dir" [p: string] {
  if not ($p | path exists) { mkdir $p }
}
