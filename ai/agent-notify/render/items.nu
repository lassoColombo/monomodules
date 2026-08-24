# Builders for the SketchyBar message args. Two kinds live here:
#   *-args    the DYNAMIC half of a paint — pure `--set`, one helper per slot
#             kind (counter chip, drawer header, agent row, preview line)
#   pool-args the STATIC half — the fixed item pool one drawer is built from,
#             carrying every property a paint never touches (fonts, paddings,
#             backgrounds, glyph, subscriptions).
# Everything is a pure function of the model: nothing here talks to the bar.

use theme.nu *

export def counter-args [item: string, state: string, n: int] {
    let tint = if $n > 0 { color $state } else { $C_SUBTLE }
    [ "--set" $item $"icon.color=($tint)" $"label=($n)" $"label.color=($tint)" ]
}

export def header-args [item: string, n: int] {
    let label = if $n == 0 { "  All clear"
        } else if $n > $ROWS { $"  ($n) active · ($ROWS) shown"
        } else { $"  ($n) active" }
    [ "--set" $"($item).item._hdr"
      $"icon=(if $n == 0 { '✓' } else { '' })"
      $"icon.color=(if $n == 0 { $C_FOAM } else { $C_SUBTLE })"
      $"label=($label)" ]
}

export def row-args [item: string, i: int, r: record] {
    let name = $"($item).item.($i)"
    [ "--set" $name $"label=($r.label)"
      $"click_script=(jump-script) ($r.session) ($r.pane_id)"
      $"script=(hover-script) ($item) ($r.session) ($r.pane_id)"
      "background.border_width=0" "drawing=on" ]
}

export def row-off-args [item: string, i: int] { ["--set" $"($item).item.($i)" "drawing=off"] }

export def pv-line-args [item: string, i: int, line: string] {
    ["--set" $"($item).item._pv.($i)" $"label=($line)" "drawing=on"]
}

export def pv-off-args [item: string] {
    0..<$PV_LINES | each {|i| ["--set" $"($item).item._pv.($i)" "drawing=off"] } | flatten
}

# One drawer's whole item pool: header + ROWS row slots + PV_LINES preview
# slots, every static property included. One message per drawer keeps each below
# any plausible IPC payload limit. Idempotent — the leading `--remove` wipes a
# previous pool so a reload can't leave orphans behind.
export def pool-args [d: record] {
    let g = glyph-of $d.state
    let c = color $d.state
    mut args = [
        "--remove" ($"/($d.item)" + '\.item\..*/')
        # counter: glyph and colour are per-drawer constants
        "--set" $d.item $"icon=($g)"
        "--add" "item" $"($d.item).item._hdr" $"popup.($d.item)"
        "--set" $"($d.item).item._hdr"
        $"icon.font=($FONT):Bold:11.0" $"label.font=($FONT):Bold:11.0"
        $"label.color=($C_SUBTLE)" $"icon.color=($C_SUBTLE)"
        "icon.padding_left=14" "label.padding_right=14" "background.drawing=off" "y_offset=1"
    ]
    for i in 0..<$ROWS {
        let n = $"($d.item).item.($i)"
        $args = $args ++ [
            "--add" "item" $n $"popup.($d.item)"
            "--set" $n "drawing=off"
            "background.drawing=on" $"background.color=($C_ROWBG)"
            "background.corner_radius=8" "background.height=30"
            "background.padding_left=8" "background.padding_right=8"
            "icon.padding_left=13" "icon.padding_right=10"
            "label.padding_left=0" "label.padding_right=18"
            $"label.color=($C_FG)" $"label.font=($FONT):Semibold:13.0"
            $"icon=($g)" $"icon.color=($c)" $"icon.font=($FONT):Bold:14.0"
            "--subscribe" $n "mouse.entered" "mouse.exited"
        ]
    }
    # Preview footer pool — hidden until a row is hovered (hover.sh) or an alert
    # opens the drawer; then filled top-down.
    for i in 0..<$PV_LINES {
        let n = $"($d.item).item._pv.($i)"
        $args = $args ++ [
            "--add" "item" $n $"popup.($d.item)"
            "--set" $n "drawing=off"
            $"label.color=($C_SUBTLE)" $"label.font=($FONT):Italic:12.0"
            "label.max_chars=80" "label.padding_left=14" "label.padding_right=14"
            # Row height = background.height (default 26 from the bar); the text is
            # ~16px, so shrink it to hug the line and kill the inter-line gap.
            "icon.drawing=off" "background.drawing=off" "background.height=16"
            $"y_offset=(if $i == 0 { 2 } else { 0 })"
        ]
    }
    $args
}

# ── Alert nudge ───────────────────────────────────────────────────────────────
# On a state change the drawer flashes open as normal — full list, header and
# all — with just the alerting pane's row highlighted. The message footer stays
# hidden (popping the whole transcript on every state change was noise, not
# signal); hover the row for it.

# Counter chip wash. Geometry only — no font change, so it can't reflow the bar.
export def alert-chip-args [item: string, state: string] {
    [ "--set" $item "background.drawing=on"
      $"background.color=(tint $state '66')"
      "background.corner_radius=6" "background.height=22"
      "background.border_width=2" $"background.border_color=(color $state)" ]
}

# Outline the alerting row and open the popup. `idx` is the row's position in the
# drawer as the last paint laid it out, so its label and click/hover wiring are
# already in place — this only re-dresses it.
export def alert-row-args [item: string, state: string, idx: int] {
    (pv-off-args $item) ++ [
      "--set" $"($item).item.($idx)"
      $"background.color=(tint $state '33')"
      "background.border_width=2" $"background.border_color=(color $state)"
      "--set" $item "popup.drawing=on" ]
}

# Close the popup and undo both highlights (chip wash, row outline).
export def alert-dismiss-args [item: string] {
    mut args = [ "--set" $item "popup.drawing=off" "background.drawing=off" "background.border_width=0" ]
    for i in 0..<$ROWS {
        $args = $args ++ [ "--set" $"($item).item.($i)"
                           "background.border_width=0" $"background.color=($C_ROWBG)" ]
    }
    $args
}
