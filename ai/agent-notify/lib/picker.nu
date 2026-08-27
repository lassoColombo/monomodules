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

# The preview pane, for an engine that has one (see `choose`). A message is prose,
# so it sits UNDER the list, spans the full width, and wraps — a picker with a
# preview pane scrolls it when the message outgrows it.
#
# Its size is what is LEFT once the list has what it needs: skim's own chrome is
# two rows (the prompt and the count), one row goes to each agent, and everything
# below — the rule that divides them included — is preview. `term size` reports
# the pane the picker is running in, so the floating drawer and an in-pane run
# each get their own honest arithmetic, and a message gets the whole screen when
# there are only two agents to choose between.
const PV_MIN = 8              # below this a message is not worth showing at all
const LIST_MIN = 3            # ...and the list is never squeezed below this to feed it
const PV_FALLBACK = "down:55%:wrap"   # no tty to measure: a share is all one can say

def preview-window [rows: int] {
    let h = (term size).rows
    if $h < 1 { return $PV_FALLBACK }
    # What the list leaves over, floored so a message stays readable — then capped,
    # because a pane too short for both is a pane where the LIST comes first.
    let want = [($h - 2 - $rows) $PV_MIN] | math max
    let pv = [$want ($h - 2 - $LIST_MIN)] | math min
    if $pv < 1 { return $PV_FALLBACK }
    $"down:($pv):wrap"
}

# Choosing goes through ONE hook: `$env.ai_config.picker`, a closure that takes
# the rows as pipeline input and an options record {prompt, display, preview,
# query, window} — see ~/.config/nushell/pickers.nu. With nothing configured this
# is Nushell's built-in `input list`, which is why nothing here depends on a
# plugin; an engine with a preview pane is handed the rendered message, and one
# that can prefill a filter is handed the query.
#
# `input list` can do neither, so the fallback does the filtering itself — a
# query that reaches an engine which ignores it would silently show you the whole
# fleet, which is worse than no query at all.
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
    # `default` would EVALUATE a closure handed to it, so spell the fallback out.
    let display = if ($opts.display? == null) { {|| $in | to text } } else { $opts.display }
    $matching | input list --fuzzy --display $display ($opts.prompt? | default "")
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
# wrote, handed to whatever `$env.ai_config.render` is (see the hook above) —
# `bat`, in this setup. With no renderer configured, or nothing to render, the
# flattened copy the store already holds is what there is: raw markdown with no
# styling reads worse than the plain text pandoc made of it.
def render-message [row: record] {
    let custom = $env.ai_config?.render?
    if ($custom == null) or (($row.md | str trim) | is-empty) { return $row.message }
    $row.md | do $custom {lang: "md"}
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
            preview: {|| render-message $in }
            window: (preview-window ($rows | length))
            query: ($query | default "")
        }
    )
    if ($picked == null) { null } else { $picked.rec }
}
