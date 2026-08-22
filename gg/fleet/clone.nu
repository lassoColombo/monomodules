use ../providers
use ../lib/config.nu

def source-completer [] { $env.gg_config? | default {} | columns }

# Clone configured source(s): clone any repos not yet present on disk, mirroring
# the provider tree under each source's `dir`. Acts on the whole fleet by default;
# pass --source to limit to one source. Idempotent — existing repos are skipped.
export def main [--source (-s): string@source-completer] {
  config resolve $source | each {|src|
    providers enumerate $src | each {|r|
      let dest = ($src.dir | path join $r.path)
      if ($dest | path exists) { return }
      mkdir ($dest | path dirname)
      git clone $r.ssh_url $dest
    }
  }
}
