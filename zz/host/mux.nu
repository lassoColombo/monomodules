# Whichever multiplexer zz is running inside: tmux when $TMUX says so, zellij
# otherwise. tmux.nu and zellij.nu have the same five commands; this is the one
# place that decides between them, so nothing else in zz has to.
use tmux.nu
use zellij.nu

def in-tmux []: nothing -> bool {
  $env.TMUX? | is-not-empty
}

# Name the focused pane.
export def rename-pane [name: string] {
  if (in-tmux) { tmux rename-pane $name } else { zellij rename-pane $name }
}

# Name the focused tab.
export def rename-tab [name: string] {
  if (in-tmux) { tmux rename-tab $name } else { zellij rename-tab $name }
}

# The layouts on disk, by bare name. Doubles as a completion source.
export def layouts []: nothing -> list<string> {
  if (in-tmux) { tmux layouts } else { zellij layouts }
}

# Pick a layout by reading it. `null` when nothing was chosen.
export def choose-layout []: nothing -> any {
  if (in-tmux) { tmux choose-layout } else { zellij choose-layout }
}

# Open a tab using the given layout, in a zoxide-picked dir.
export def tab [layout: string, prompt: string, query?: string] {
  if (in-tmux) { tmux tab $layout $prompt $query } else { zellij tab $layout $prompt $query }
}
