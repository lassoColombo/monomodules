# SketchyBar integration: renders the on-disk store as a stacked, clickable
# notification popup. "Notifications" = agents currently in an attention state
# (● awaiting / ▲ needs-attention), across all live sessions.
#
#   agent-notify sketchybar          rebuild the popup + anchor label (on event)
#   agent-notify sketchybar toggle   show/hide the drawer (bound to a keybind)
#   agent-notify sketchybar close    hide the drawer (after a jump)
#
# The anchor item `notify` and the bar itself are defined in sketchybarrc; this
# module only (re)populates them. Uses absolute paths so it works from the
# minimal env of a SketchyBar plugin or an aerospace keybind.

use lib/const.nu *
use lib/store.nu *

const SB = "/opt/homebrew/bin/sketchybar"
const JUMP = $"($nu.home-dir)/.config/sketchybar/plugins/jump.sh"

# Agents currently needing the user, most-urgent first.
def pending [] {
    store-list
    | where state in ["needs-attention" "awaiting"]
    | insert _pri {|r| if $r.state == "needs-attention" { 0 } else { 1 } }
    | sort-by _pri updated_at
}

# Compact "▲N ●M" summary for the anchor label (like the tab aggregate).
def summarize [items: list] {
    let na = $items | where state == "needs-attention" | length
    let nw = $items | where state == "awaiting" | length
    let parts = [
        (if $na > 0 { $"($S_NEED)($na)" })
        (if $nw > 0 { $"($S_WAIT)($nw)" })
    ] | compact
    if ($parts | is-empty) { "—" } else { $parts | str join " " }
}

export def main [] {
    let items = pending
    # Wipe old popup rows, then rebuild.
    ^$SB --remove '/notify\.item\..*/' | complete | ignore
    ^$SB --set notify $"label=(summarize $items)" | complete | ignore
    for row in ($items | enumerate) {
        let it = $row.item
        let name = $"notify.item.($row.index)"
        let label = $"(state-glyph $it.state)  ($it.agent) · ($it.session)/($it.tab_name) · ($it.base)"
        ^$SB --add item $name popup.notify | complete | ignore
        ^$SB --set $name $"label=($label)" $"click_script=($JUMP) ($it.session) ($it.pane_id)" | complete | ignore
    }
}

export def toggle [] {
    # Key off bar.hidden (queryable); popup.drawing is not exposed via --query.
    let hidden = try { ^$SB --query bar | from json | get hidden } catch { "on" }
    if $hidden == "on" {
        main
        ^$SB --bar hidden=off --set notify popup.drawing=on | complete | ignore
    } else {
        close
    }
}

export def close [] {
    ^$SB --set notify popup.drawing=off --bar hidden=on | complete | ignore
}
