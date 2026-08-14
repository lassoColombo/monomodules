# Rosé Pine — re-apply the tinty configuration.
#
# Source of truth lives under ~/.config/tinted-theming/. This module exposes a
# single command (the directory module's `main`, callable as `rose-pine`): it
# re-renders every .mustache template via tinted-builder-rust, then applies the
# scheme through tinty so each tool's config is rewritten. Run it after editing
# scheme.yaml or any template.

# Completer: all scheme ids known to tinty (custom first, then standard).
def "nu-complete schemes" []: nothing -> list<string> {
  ^tinty list --custom-schemes --json | from json | get id
  | append (^tinty list --json | from json | get id)
}

# Fail loudly on a captured external result. tinty swallows hook failures (e.g.
# a stale cp target) and still exits 0, so a non-empty stderr is treated as an
# error too — not just a nonzero exit code.
def check [cmd: string]: record -> nothing {
  let r = $in
  if $r.exit_code != 0 or ($r.stderr | str trim | is-not-empty) {
    error make { msg: $"($cmd) failed \(exit ($r.exit_code)):\n($r.stderr | str trim)" }
  }
}

# Re-render templates and apply the scheme. Defaults to base24-rose-pine.
export def main [
  --scheme: string@"nu-complete schemes" = "base24-rose-pine"  # scheme id to apply
]: nothing -> nothing {
  let base = "~/.config/tinted-theming" | path expand
  let custom_schemes = "~/.local/share/tinted-theming/tinty/custom-schemes" | path expand
  ^tinted-builder-rust build $base --schemes-dir $custom_schemes | complete | check "tinted-builder-rust build"
  ^tinty apply $scheme --quiet | complete | check "tinty apply"
}
