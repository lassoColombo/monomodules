# The escape sequences, named once — and the two terminal modes the picker
# borrows, so that giving them back is one call and not a checklist.
#
# Named `tty.nu`, NOT `term.nu`: `term` is a builtin (`term size`), and a module
# by that name would sit in front of it for everything that imports this (§10).
#
# ── THE FRAME IS NEVER CLEARED ────────────────────────────────────────────────
# The obvious repaint is "home the cursor, erase the screen, print" — and it
# FLASHES, because for one frame the terminal really is empty. With a heartbeat
# redrawing every couple of seconds you would watch it blink for as long as the
# picker is open.
#
# So nothing is ever erased in advance. The cursor goes home, each line is
# written OVER the line already there and finished with `EL` (erase to end of
# line) to take away whatever was longer, and one `ED` (erase below) at the end
# removes any rows a shorter frame left behind. The screen is only ever
# overwritten, so there is no blank moment to see.
#
# ── AUTOWRAP OFF ──────────────────────────────────────────────────────────────
# A single line too long for the terminal wraps onto the next row and pushes
# every row below it down — which corrupts the frame and, because the next
# repaint homes to the top, keeps it corrupted. The preview is an arbitrary other
# program's screen, so "too long" is not hypothetical.
#
# Measuring display columns from nushell is not possible (a grapheme is not a
# column, and East Asian width is not a string length), so the picker does not
# try to be exact: `layout.nu` clips generously, and DECAWM off makes the
# terminal itself responsible for the last column. Correct by construction
# rather than by arithmetic.
#
# ── AND THE CURSOR IS LEFT VISIBLE ────────────────────────────────────────────
# Hiding it would mean owning its return, and `browse` runs IN PLACE (D52): a
# crash between hide and show leaves your own pane with no cursor for the rest of
# the session. Instead it is parked at the end of what you have typed, where it
# reads as the filter's caret. Nothing to restore, nothing to leak.

const ESC = "\u{1b}"

const HOME = "\u{1b}[H"          # cursor to row 1, column 1
const EL = "\u{1b}[K"            # erase from the cursor to the end of the line
const ED = "\u{1b}[J"            # erase from the cursor to the end of the screen
const WRAP_OFF = "\u{1b}[?7l"    # DECAWM off — a long line is clipped, not wrapped
const WRAP_ON = "\u{1b}[?7h"
const CURSOR_ON = "\u{1b}[?25h"

# What to emit before the first frame.
export def setup []: nothing -> string { $WRAP_OFF }

# …and after the last one, on every exit path including a failed one.
# `CURSOR_ON` is not ours to need — nothing here hides it — but a program that
# ran in this pane before us may have, and one byte is cheaper than a pane you
# cannot type in.
export def restore []: nothing -> string { $WRAP_ON + $CURSOR_ON + "\r\n" }

# One frame, ready for `print -n`. `caret` is the 1-based column the cursor ends
# on, which `layout caret` works out from what has been typed.
export def paint [lines: list<string>, caret: int]: nothing -> string {
    let body = $lines | each {|l| $l + $EL } | str join "\r\n"
    let col = [$caret 1] | math max
    $HOME + $body + $ED + $"($ESC)[1;($col)H"
}
