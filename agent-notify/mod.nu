# Decorates the current zellij pane/tab name with an "(<agent> <emoji>) - <base>"
# prefix that reflects an AI agent's state. The base name is preserved across
# state changes by stripping any existing "(<word> ...) - " prefix first.
# Targets the pane the caller runs in via $ZELLIJ_PANE_ID. No-op outside zellij.

const markers = ["☠️" "🔔" "🧠"]

def strip-marker [name: string] {
    mut s = $name | str trim
    let parsed = $s | parse --regex '^\([^)]*\)\s*-\s*(?<base>.*)$'
    if not ($parsed | is-empty) {
        $s = $parsed | get base.0 | str trim
    }
    for m in $markers {
        if ($s | str starts-with $m) {
            $s = ($s | str substring ($m | str length)..) | str trim
        }
    }
    $s
}

def pane-info [pane_id: int] {
    ^zellij action list-panes -t -j
    | from json
    | where id == $pane_id
    | get -o 0
}

def format-name [agent: string, symbol: string, base: string] {
    let head = if ($symbol | is-empty) { $"\(($agent)\)" } else { $"\(($agent) ($symbol)\)" }
    if ($base | is-empty) { $head } else { $"($head) - ($base)" }
}

def apply [agent: string, symbol: string] {
    if ($env.ZELLIJ? | is-empty) { return }
    let pane_id_str = $env.ZELLIJ_PANE_ID? | default ""
    if ($pane_id_str | is-empty) { return }
    let pane_id = ($pane_id_str | into int)
    let info = pane-info $pane_id
    if $info == null { return }

    let pane_base = strip-marker $info.title
    let tab_base = strip-marker $info.tab_name

    ^zellij action rename-pane --pane-id $pane_id_str (format-name $agent $symbol $pane_base)
    ^zellij action rename-tab --tab-id $info.tab_id (format-name $agent $symbol $tab_base)
}

# SessionStart: prefix current pane and tab names with "(<agent>) - ".
# Optional `name` parameter overrides the pane base; tab always uses its
# current name as base.
export def session-start [agent: string, name?: string] {
    if ($env.ZELLIJ? | is-empty) { return }
    let pane_id_str = $env.ZELLIJ_PANE_ID? | default ""
    if ($pane_id_str | is-empty) { return }
    let pane_id = ($pane_id_str | into int)
    let info = pane-info $pane_id
    if $info == null { return }

    let pane_base = if ($name | is-empty) { strip-marker $info.title } else { $name }
    let tab_base = strip-marker $info.tab_name

    ^zellij action rename-pane --pane-id $pane_id_str (format-name $agent "" $pane_base)
    ^zellij action rename-tab --tab-id $info.tab_id (format-name $agent "" $tab_base)
}

# Prepend "(<agent> ☠️) - " — agent is blocked, needs user attention.
export def needs-attention [agent: string] {
    apply $agent "☠️"
}

# Prepend "(<agent> 🧠) - " — agent is actively working.
export def working [agent: string] {
    apply $agent "🧠"
}

# Prepend "(<agent> 🔔) - " — agent has returned control, your turn.
export def awaiting [agent: string] {
    apply $agent "🔔"
}

# Remove any "(<word> ...) - " prefix from current pane/tab name.
export def clear [] {
    if ($env.ZELLIJ? | is-empty) { return }
    let pane_id_str = $env.ZELLIJ_PANE_ID? | default ""
    if ($pane_id_str | is-empty) { return }
    let pane_id = ($pane_id_str | into int)
    let info = pane-info $pane_id
    if $info == null { return }

    let pane_base = strip-marker $info.title
    let tab_base = strip-marker $info.tab_name

    let pane_name = if ($pane_base | is-empty) { " " } else { $pane_base }
    let tab_name = if ($tab_base | is-empty) { " " } else { $tab_base }

    ^zellij action rename-pane --pane-id $pane_id_str $pane_name
    ^zellij action rename-tab --tab-id $info.tab_id $tab_name
}
