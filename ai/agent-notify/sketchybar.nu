# SketchyBar integration: projects the live pane scan onto one pill of three
# per-state counters (a bracket), each a button opening its own drawer.
#   ◦ agents_run   working         — button → drawer listing these agents
#   ▴ agents_attn  needs-attention — button → drawer listing these agents
#   • agents_stale awaiting        — button → drawer listing these agents
# No store — a killed pane simply isn't in the scan, so a drawer can't ghost.
#
#   ai agent-notify sketchybar   rebuild the counters + drawers from live panes
#
# The counters always refresh; each drawer's ITEMS only rebuild while it's CLOSED
# (re-adding under the cursor makes SketchyBar collapse it). One batched
# invocation per drawer → no flicker. Absolute paths for a bar plugin's minimal env.

use lib/const.nu *
use lib/title.nu *
use lib/zellij.nu *

const SB = "/opt/homebrew/bin/sketchybar"
const JUMP = $"($nu.home-dir)/.config/sketchybar/plugins/jump.sh"

# Rosé Pine ARGB (mirrors colors.sh) — kept inline so the module needs no theme file.
const C_FG     = "0xffe0def4"
const C_SUBTLE = "0xff8c88a6"
const C_ROWBG  = "0xff26233a"   # overlay / base02 — subtle row lift over the popup
const C_FOAM   = "0xff9ccfd8"
const C_GOLD   = "0xfff6c177"
const C_LOVE   = "0xffeb6f92"
const C_ACCENT = "0xffc4a7e7"
const FONT     = "MesloLGLDZ Nerd Font"

# The three counter items (mirror the bracket members in sketchybarrc).
const W_RUN   = "agents_run"    # working — button + drawer
const W_ATTN  = "agents_attn"   # needs-attention — button + drawer
const W_STALE = "agents_stale"  # awaiting — button + drawer

# Rosé Pine accent per state: needs-attention = love, awaiting = gold, working = foam.
def state-color [state: string] {
    if $state == "needs-attention" { $C_LOVE } else if $state == "awaiting" { $C_GOLD } else { $C_FOAM }
}

# Live agent panes (any active state), most-urgent first. Callers filter by state.
def agent-rows [panes: table] {
    $panes
    | each {|p|
        let t = parse-title $p.title
        {
            state: (state-name $t.symbol)
            tab: (parse-title $p.tab_name).base
            pane: $t.base
            session: $p.session
            pane_id: $p.id
            tab_position: $p.tab_position
        }
    }
    | where state in ["needs-attention" "awaiting" "working"]
    | insert _pri {|r| if $r.state == "needs-attention" { 0 } else if $r.state == "awaiting" { 1 } else { 2 } }
    | sort-by _pri session tab_position pane_id
}

# Set one counter widget: glyph icon + numeric label, tinted when active, dim at
# zero. Always drawn — the pill stays a stable anchor even when idle.
def set-count [item: string, glyph: string, n: int, color: string] {
    let tint = if $n > 0 { $color } else { $C_SUBTLE }
    ^$SB --set $item $"icon=($glyph)" $"icon.color=($tint)" $"label=($n)" $"label.color=($tint)" | complete | ignore
}

# Rebuild one drawer's rows from its agents — unless it's open (re-adding under
# the cursor collapses it). Rows are clickable → jump to the pane.
def build-drawer [item: string, rows: table] {
    let open = try { ^$SB --query $item | from json | get popup.drawing } catch { "off" }
    if $open == "on" { return }

    let rm = $"/($item)" + '\.item\..*/'
    mut args = [ "--remove" $rm ]

    # Header row: "N active", or an all-clear line when empty.
    let empty = ($rows | is-empty)
    let hdr = if $empty { "  All clear" } else { $"  ($rows | length) active" }
    let hdr_icon = if $empty { $C_FOAM } else { $C_SUBTLE }
    $args = $args ++ [
        "--add" "item" $"($item).item._hdr" $"popup.($item)"
        "--set" $"($item).item._hdr"
        $"icon=(if $empty { '✓' } else { '' })" $"icon.color=($hdr_icon)" $"icon.font=($FONT):Bold:11.0"
        $"label=($hdr)" $"label.color=($C_SUBTLE)" $"label.font=($FONT):Bold:11.0"
        "icon.padding_left=14" "label.padding_right=14" "background.drawing=off" "y_offset=1"
    ]

    # One styled, clickable row per agent.
    for row in ($rows | enumerate) {
        let it = $row.item
        let name = $"($item).item.($row.index)"
        # session/tab · pane — drop the middle when the pane name equals the tab.
        let label = if ($it.pane == $it.tab) or ($it.pane | is-empty) {
            $"($it.session)/($it.tab)"
        } else {
            $"($it.session)/($it.tab)  ·  ($it.pane)"
        }
        $args = $args ++ [
            "--add" "item" $name $"popup.($item)"
            "--set" $name
            "background.drawing=on" $"background.color=($C_ROWBG)"
            "background.corner_radius=8" "background.height=30"
            "background.padding_left=8" "background.padding_right=8"
            "icon.padding_left=13" "icon.padding_right=10"
            "label.padding_left=0" "label.padding_right=18"
            $"label.color=($C_FG)" $"label.font=($FONT):Semibold:13.0"
            $"icon=(state-glyph $it.state)" $"icon.color=(state-color $it.state)" $"icon.font=($FONT):Bold:14.0"
            $"label=($label)"
            $"click_script=($JUMP) ($it.session) ($it.pane_id)"
        ]
    }

    # Re-check: the drawer may have opened during the (slow) scan above.
    let open2 = try { ^$SB --query $item | from json | get popup.drawing } catch { "off" }
    if $open2 == "on" { return }
    ^$SB ...$args | complete | ignore
}

# Rebuild the three counters + both drawers from a scan (defaults to a fresh one).
# Counters always refresh; drawer rows only rebuild while their drawer is closed.
export def render-popup [panes?: any] {
    let sc = if ($panes == null) { scan } else { $panes }

    # The three counters — counted over the whole scan (working included).
    let syms = $sc | each {|p| (parse-title $p.title).symbol }
    set-count $W_RUN   $S_WORK ($syms | where {|s| $s == $S_WORK } | length) $C_FOAM
    set-count $W_ATTN  $S_NEED ($syms | where {|s| $s == $S_NEED } | length) $C_LOVE
    set-count $W_STALE $S_WAIT ($syms | where {|s| $s == $S_WAIT } | length) $C_GOLD

    # The three clickable drawers, each listing its own state.
    let ag = agent-rows $sc
    build-drawer $W_RUN   ($ag | where state == "working")
    build-drawer $W_ATTN  ($ag | where state == "needs-attention")
    build-drawer $W_STALE ($ag | where state == "awaiting")
}

# `ai agent-notify sketchybar` — render the counters + drawers from a fresh scan.
export def main [] { render-popup }
