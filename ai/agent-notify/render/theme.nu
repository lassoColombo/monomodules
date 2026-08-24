# Bar-side presentation constants: palette, fonts, geometry, and the location of
# the SketchyBar glue scripts a row wires itself to. Everything here is about how
# the drawers LOOK; the row text, glyphs and ordering come from
# agent-notify/lib/view.nu, shared with the terminal picker so the two surfaces
# can never drift apart.

export use ../lib/view.nu *

export const SB = "/opt/homebrew/bin/sketchybar"
export const FONT = "MesloLGLDZ Nerd Font"

export const C_FG     = "0xffe0def4"
export const C_SUBTLE = "0xff8c88a6"
export const C_ROWBG  = "0xff26233a"
export const C_FOAM   = "0xff9ccfd8"   # working
export const C_GOLD   = "0xfff6c177"   # awaiting / stale
export const C_LOVE   = "0xffeb6f92"   # needs-attention

export const W_RUN   = "agents_run"
export const W_STALE = "agents_stale"
export const W_ATTN  = "agents_attn"

# Row slots per drawer. A hard cap by design: agents past it are counted in the
# header rather than rendered (an endless drawer is unusable anyway).
export const ROWS = 10

# Preview footer: a pool of line-items per drawer (SketchyBar labels are
# single-line, so a multi-line message is spread across several). Wrapped to
# PV_WIDTH cols, capped at PV_LINES rows (last row gets an ellipsis if longer).
export const PV_LINES = 12
export const PV_WIDTH = 62

# The three drawers, in bar order: which state each one collects.
export def drawer-specs [] {
    [ {item: $W_RUN, state: "working"}
      {item: $W_STALE, state: "awaiting"}
      {item: $W_ATTN, state: "needs-attention"} ]
}

# Which drawer a state's agents live in.
export def drawer-of [state: string] { if $state == "needs-attention" { $W_ATTN } else { $W_STALE } }

# state → colour: the bar-side half of the mapping (the glyphs are `glyph-of`).
export def color [s: string] { if $s == "needs-attention" { $C_LOVE } else if $s == "awaiting" { $C_GOLD } else if $s == "working" { $C_FOAM } else { $C_SUBTLE } }

# Same hue at low alpha — used to wash the alerted row/counter during a peek.
export def tint [s: string, alpha: string] { $"0x($alpha)(color $s | str substring 4..)" }

# The bar's own glue scripts, which a row's click/hover wires itself to. They
# belong to the SketchyBar config, not to this module, so the directory is
# overridable — the bar is a consumer that can live anywhere.
def plugin-dir [] {
    $env.AGENT_NOTIFY_BAR_PLUGINS? | default ([$env.HOME .config sketchybar plugins] | path join)
}

export def jump-script [] { [(plugin-dir) jump.sh] | path join }
export def hover-script [] { [(plugin-dir) hover.sh] | path join }
