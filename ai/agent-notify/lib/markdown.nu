# Markdown → plain text for stored previews. Agents write markdown; every
# surface that shows a preview is plain text (a SketchyBar label takes one font
# and one colour, so styling cannot survive the trip anyway), and the raw syntax
# is pure noise once it can't be rendered.
#
# This runs ONCE, where the preview is stored (see mod.nu), not per render — so
# both surfaces read clean text out of the store at no cost, and the ~30ms is
# paid on the hook path, which already spawns nu and talks to zellij.
#
# pandoc does the work; it is optional, and anything unexpected — missing
# binary, non-zero exit, empty output — falls back to the raw message, so a
# machine without it behaves exactly as before.

# Longest input worth converting. The surfaces show at most ~750 characters
# (12 lines × 62 cols), so this is slack, not a limit anyone can feel — it just
# stops a pathological message from being handed to a subprocess whole.
const MAX_IN = 4000

# Mirrors the NARROWER of the two surfaces (render/theme.nu's PV_WIDTH). Only
# reaches things pandoc has to lay out itself — rules and tables — so sizing to
# the bar keeps those from overrunning it; the terminal just shows them narrow.
const COLUMNS = 62

# Cheap "is there anything to convert?" test, so the common short notification
# ("Claude needs your permission") never pays for a subprocess.
def plain-already [text: string] {
    (not ($text | str contains "\n")) and (not ($text =~ '[`*#\[\]>|_~]'))
}

export def to-plain [text?: string] {
    let t = $text | default "" | str trim
    if ($t | is-empty) or (plain-already $t) { return $t }

    let r = try { $t | str substring 0..<$MAX_IN | ^pandoc -f gfm -t plain --wrap=none --columns=($COLUMNS) | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) or (($r.stdout | str trim) | is-empty) { return $t }

    $r.stdout
        # Two things the plain writer leaves behind: a thematic break becomes a
        # full-width run of dashes (a whole preview line spent on nothing), and
        # strikethrough has no plain form at all, so its tildes pass through.
        | lines | where {|l| not ($l =~ '^\s*-{8,}\s*$') } | str join "\n"
        | str replace --all "~~" ""
        | str trim
}
