use ../providers
use ../lib/config.nu

def source-completer [] { $env.gg_config? | default {} | columns }

# List the remote repos of configured source(s). Enumeration only — no disk writes.
# Omit `source` to list every configured source.
export def main [source?: string@source-completer]: nothing -> table {
  config resolve $source | each {|src|
    providers enumerate $src | select path ssh_url | insert source $src.name | select source path ssh_url
  } | flatten
}
