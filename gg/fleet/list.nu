use ../providers
use ../lib/config.nu

def source-completer [] { $env.gg_config? | default {} | columns }

# List the remote repos of configured source(s). Enumeration only — no disk writes.
# Acts on the whole fleet by default; pass --source to limit to one source.
export def main [--source (-s): string@source-completer]: nothing -> table {
  config resolve $source | each {|src|
    providers enumerate $src | select path ssh_url | insert source $src.name | select source path ssh_url
  } | flatten
}
