# Provider dispatch — enumerate a source's remote repos into a normalized table.
# Internal to gg (imported by the fleet commands); NOT part of the command surface.
use gitlab.nu
use github.nu

# Enumerate a source's remote repos -> table<{path, ssh_url}>. Dispatches on provider.
export def enumerate [source: record]: nothing -> table {
  match $source.provider {
    "gitlab" => (gitlab enumerate $source)
    "github" => (github enumerate $source)
    _ => (error make --unspanned {msg: $"gg: unknown provider '($source.provider? | default '')' for source '($source.name? | default '?')'"})
  }
}
