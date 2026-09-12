# Terminal twin of the SketchyBar drawers: the live agents as a fuzzy-filterable
# list, with the highlighted agent's message in a preview pane under it. Returns
# the chosen record, or null when there is nothing to show or the user cancels.
# Presentation ONLY — the `browse` verb in mod.nu owns the jump.
#
# skim (the `sk` command from nu_plugin_skim) owns every bit of chrome: the
# frame, the filtering, the preview window and its wrapping and scrolling. This
# file only says WHAT a row and a preview hold, and it says it with lib/view.nu —
# the same helpers the bar paints with — so the two surfaces cannot drift apart.
#
# Rows go in as records and come back as records: the picker returns the item it
# was given, so the selection maps straight back to its store record — no ids, no
# lookup table. Row strings are built once, eagerly; the message is rendered only
# for the agent under the cursor, which is why the preview is a closure.

use view.nu *

# Choosing goes through ONE hook: `$env.ai_config.picker`, a closure that takes
# the rows as pipeline input and an options record {prompt, display, preview,
# query} — see ~/.config/nushell/module-hooks.nu. This file says what a row and a
# preview HOLD and nothing about how either looks: the frame, the sizing, the
# preview pane and every key are the picker's, which is why nothing handed over
# here is a number.
#
# With nothing configured the picker is Nushell's built-in `input list`, which is
# why nothing here depends on a plugin. It has no preview pane and drops
# `preview` on the floor, and it cannot prefill a filter — so the ONE thing this
# fallback does for itself is apply the query, because a query that reaches an
# engine which ignores it would silently show you the whole fleet, which is worse
# than no query at all.
def choose [opts: record] {
    let rows = $in
    let custom = $env.ai_config?.picker?
    if ($custom != null) { return ($rows | do $custom $opts) }

    let q = $opts.query? | default ""
    let matching = if ($q | is-empty) { $rows } else {
        $rows | where {|r| ($r.row | ansi strip | str lowercase) =~ ($q | str lowercase) }
    }
    if ($matching | is-empty) {
        print $"(ansi dark_gray)no agent matches ($q)(ansi reset)"
        return null
    }
    $matching | input list --fuzzy --display $opts.display $opts.prompt
}

# state → terminal colour: the palette-facing half of the mapping the bar makes
# with its own hex values. ANSI names, so the terminal theme stays in charge —
# the shapes themselves are `glyph-of`, shared with every other surface. A picker
# keeps these colours on the selected row and paints its own match highlight over
# them (skim's palette comes from $env.SKIM_DEFAULT_OPTIONS).
def color-of [state: string] {
    if $state == "needs-attention" { ansi light_red_bold
    } else if $state == "awaiting" { ansi yellow_bold
    } else if $state == "working" { ansi cyan
    } else { ansi dark_gray }
}

# The rows to choose from, most urgent first (`sort-agents`): `row` is what skim
# shows AND, colours stripped, what it fuzzy-matches — so a state, a tab name or
# a phrase from the message all narrow the list; `message` is the readable copy
# for the preview pane; `rec` is the record to hand back.
#
# Three columns, the first two padded so the eye can run down them. An idle agent
# has no glyph, so it gets a space in its place — the same trick `bare-title`
# plays on the titles, for the same reason. Widths are counted in CHARACTERS:
# plain `str length` counts bytes, and a "·" in a label would buy itself a column
# of padding it does not occupy.
def rows-of [recs: list<any>] {
    let cells = sort-agents $recs | each {|r| {
        state: ($r.state? | default "idle")
        label: (label $r)
        text: ($r.preview? | default "" | str trim)
        md: ($r.preview_md? | default "")
        rec: $r
    } }
    let w_state = $cells | each {|c| $c.state | str length --grapheme-clusters } | append 0 | math max
    let w_label = $cells | each {|c| $c.label | str length --grapheme-clusters } | append 0 | math max

    $cells | each {|c|
        let g = glyph-of $c.state
        let mark = if ($g | is-empty) { " " } else { $g }
        {
            row: $"(color-of $c.state)($mark) ($c.state | fill --width $w_state)(ansi reset)  ($c.label | fill --width $w_label)  (ansi dark_gray)(one-line $c.text)(ansi reset)"
            md: $c.md
            message: (if ($c.text | is-empty) { "— no message —" } else { $c.text })
            rec: $c.rec
        }
    }
}

# The message as the preview pane should show it: the markdown the agent actually
# wrote, or — when the store has no markdown copy — the flattened text it does
# have. Text, and nothing else.
#
# STYLING it is the PICKER'S business (see `choose`), which is why there is no
# second hook here and nothing in this file knows what `bat` is. A picker that
# highlights markdown wraps this closure in its own; one that cannot shows the
# source, which is what an unstyled preview has always been.
def message-of [row: record] {
    if (($row.md | str trim) | is-empty) { $row.message } else { $row.md }
}

# Present the agents, return the picked record (null on cancel / nothing to show).
# `query` prefills the filter where the picker can take one: it leaves you in the
# list with a "0/n" count and a backspace, not staring at an error.
export def pick [recs: list<any>, query?: string] {
    let rows = rows-of $recs
    if ($rows | is-empty) { print $"(ansi dark_gray)no agents(ansi reset)"; return null }

    let picked = (
        $rows
        | choose {
            prompt: "agent"
            display: {|| $in.row }
            preview: {|| message-of $in }
            query: ($query | default "")
        }
    )
    if ($picked == null) { null } else { $picked.rec }
}
