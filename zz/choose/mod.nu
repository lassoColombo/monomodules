# zz's two pickers, and the one switch between them.
#
# `sk` (the nu_plugin_skim command) has a preview pane; Nushell's own `input
# list` does not. That is the only difference that matters, and skim.nu exists
# entirely to serve it — the pane's position, its size, the keys that scroll it,
# and the width it hands to a preview closure.
#
# Nothing in here knows what it is choosing between. Items in, one record of
# closures saying how they read, one item out — pick/ is the file that binds a
# zoxide entry to that contract.
#
# Flip SK to false and zz is back on the built-in picker, with every preview
# closure left uncalled. Nothing outside this module is consulted: zz is nobody's
# library, so it makes its own choice rather than reading it from a config hook.
#
# The plugin check is the same switch thrown on zz's behalf. `sk` parses fine
# without the plugin registered and only fails when called, and the `-n`
# launchers (zellij's Alt-a binding) start a Nushell with no plugin registry at
# all — zz should quietly use the built-in there rather than break.
use skim.nu
use builtin.nu

const SK = true

def ready []: nothing -> bool {
  $SK and (plugin list | where name == "skim" | is-not-empty)
}

# Both pickers take the items as pipeline input and one record:
#
#   {prompt: string, display: closure, preview: closure, multi: bool}
#
# `display` renders one item as its row, the item on `$in`. `preview` renders it
# into the pane — the item on `$in` again, the pane's WIDTH as a parameter — and
# is simply never called by the picker that has no pane.
#
# `null` when nothing was chosen, from either of them.
export def main [opts: record] {
  if (ready) { $in | skim pick $opts } else { $in | builtin pick $opts }
}
