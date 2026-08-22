# gg fleet configuration — the declared desired state.
#
# `$env.gg_config` is a record keyed by a source handle (the name you type).
# Each entry declares one GitLab group / GitHub org to mirror locally:
#
#   $env.gg_config = {
#     elmec:    { provider: gitlab, host: "git.elmec.com", group: "platform", dir: "~/work/elmec" }
#     personal: { provider: github, org: "lasso", dir: "~/projects/personal" }
#   }
#
# See gg/README.md for the full field reference.

# provider -> default API host
const HOST_DEFAULT = { gitlab: "git.elmec.com", github: "github.com" }

# Raw config record (empty if unset).
export def read []: nothing -> record {
  $env.gg_config? | default {}
}

# All configured source handles.
export def sources []: nothing -> list<string> {
  read | columns
}

# Normalize one entry: attach its handle, default the host per provider, expand dir.
def normalize [name: string, entry: record]: nothing -> record {
  let provider = ($entry.provider? | default "")
  if ($provider not-in [gitlab github]) {
    error make --unspanned {msg: $"gg: source '($name)' has invalid provider '($provider)' \(want gitlab or github\)"}
  }
  if (($entry.dir? | default "") | is-empty) {
    error make --unspanned {msg: $"gg: source '($name)' is missing 'dir'"}
  }
  $entry | merge {
    name: $name
    host: ($entry.host? | default ($HOST_DEFAULT | get $provider))
    dir: ($entry.dir | path expand)
  }
}

# Resolve a source by handle — or every source when omitted — to normalized records.
export def resolve [name?: string]: nothing -> list<record> {
  let cfg = read
  if ($cfg | is-empty) {
    error make --unspanned {msg: "gg: $env.gg_config is empty — declare at least one source (see gg/README.md)"}
  }
  if ($name | is-empty) {
    return ($cfg | items {|name, entry| normalize $name $entry })
  } 
  let entry = ($cfg | get -o $name)
  if ($entry == null) {
    error make --unspanned {msg: $"gg: no source named '($name)' \(configured: ($cfg | columns | str join ', ')\)"}
  }
  [(normalize $name $entry)]
}
