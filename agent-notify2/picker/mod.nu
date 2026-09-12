# The picker: a list of agents, a live preview of the one under the cursor, and
# the id of whichever you chose.
#
# THE ONLY IMPURE FILE IN THIS DIRECTORY. Four calls touch the world — read the
# store, read a screen, print, read a key — and everything between them is a pure
# function living in `rows.nu`, `frame.nu` or `keys.nu`, each with its own
# assertions. That is deliberate: an event loop is the one part a suite cannot
# drive, so it is kept to the four lines that must be here.
#
#   loop {
#       records ← the store          re-read EVERY frame: 0.33ms, so the list is live
#       rows    ← build, narrow      pure
#       view    ← settle             pure: the selection still exists? scrolled?
#       preview ← the locator        the agent's real terminal, 12ms
#       lines   ← render             pure: the whole screen, as strings
#       print IF THE FRAME MOVED     unchanged ⇒ not one byte
#       key     ← input listen       blocks; beats every 2s so the preview stays live
#       view    ← step               pure
#   }
#
# ── WHY IT OWNS THE LOOP ─────────────────────────────────────────────────────
# `input list` cannot do this. It is OPAQUE: it blocks and reports nothing until
# you press enter, so there is no moment at which anything else could redraw a
# preview beside it. Every design that kept it needed a SECOND process watching
# the picker's screen and parsing the highlight back out — which was built, and
# worked, and was rejected for being able to break silently.
#
# Owning the loop is resilient through three ABSENCES. Nothing to parse: we set
# the selection, so we know it. Nothing to poll: `input listen` blocks until a
# key arrives. Nothing to coordinate: one pane, one process, no focus juggling
# and no pane to orphan.
#
# ── THE HEARTBEAT, AND WHY IT IS A TIMED FAILURE ─────────────────────────────
# `--timeout` makes a quiet moment into a redraw, which is what keeps the preview
# LIVE while you sit still — you watch an agent working. nushell delivers that
# expiry as an ERROR rather than as a null, so it has to be caught.
#
# And catching it is exactly where a picker can be made to spin. `catch { null }`
# reads "there is no terminal" the same way it reads "nothing happened", so with
# stdin closed the loop turns over about 37,000 times a second forever, each pass
# trying to spawn a `dump-screen`. Measured. So the catch is TIMED instead: a
# timeout that did not take the timeout's worth of time was not a timeout.
#
# Timed rather than matched on the message text, because the wording belongs to
# nushell and a reworded error would otherwise mean the picker exits instantly on
# every heartbeat.

use ../core/store.nu
use rows.nu
use frame.nu
use keys.nu
use tty.nu

# Long enough that a quiet picker is nearly free (12ms of dump per 2s), short
# enough that a preview feels live.
const BEAT = 2sec

# Under this, the listen cannot have waited out the beat — so it failed for some
# other reason, and the only one that matters is "there is no terminal here".
const QUICK = 200ms

# What the preview shows: the agent's real screen, or — when there is none — what
# it last said, as the markdown it wrote.
#
# The two are cut from opposite ends, which is not an inconsistency. A live
# screen's BOTTOM is what is current. A message's TOP is the point.
def preview-of [row: any, height: int]: nothing -> list<string> {
    if ($row == null) or ($height < 1) { return [] }
    let live = if ($row.via == null) { [] } else {
        try { do $row.via.screen $row.rec $height } catch { [] }
    }
    if ($live | is-not-empty) { return $live }

    let said = $row.rec.message? | default "" | str trim
    if ($said | is-empty) { return ["(nothing to show)"] }
    $said | lines | first $height
}

# One turn of the loop, over and over. Returns the chosen ROW, or null.
def drive [query: string, table?: record]: nothing -> any {
    mut view = {sel: "", query: $query, top: 0}
    mut painted = []

    loop {
        # `table` is null unless a test overrode it; `rows build` resolves the
        # shipped locators from that, so the default lives in one place.
        let all = rows build (store list) $table
        let shown = rows narrow $all ($view.query)
        let lay = frame layout (term size) ($shown | length)
        $view = rows settle $view $shown $lay.list

        let lines = frame render $shown $view $lay (preview-of (rows selected $shown $view) $lay.preview)
        if $lines != $painted {
            print -n (tty paint $lines (frame caret $view))
            $painted = $lines
        }

        # See the header: the catch is timed, not trusted.
        let began = date now
        let ev = try { input listen --types [key] --timeout $BEAT } catch { null }
        if $ev == null {
            if ((date now) - $began) < $QUICK {
                error make --unspanned {msg: ("browse needs a terminal — run it in one, "
                    + "or bind it to a floating pane with `agent-notify2 browse wiring`")}
            }
            continue
        }

        let next = keys step $ev $view $shown
        if $next.action == "cancel" { return null }
        if $next.action == "jump" { return (rows selected $shown $next.view) }
        $view = $next.view
    }
}

# Pick an agent. Returns the chosen ROW — which carries both the record and the
# locator that claimed it — or null if you changed your mind.
#
# IT DOES NOT JUMP. The caller decides what a choice means, which is what lets a
# future "show me what agent X is doing" reuse every line of this without going
# anywhere. `cli/browse.nu` is the caller that jumps.
#
# No `-> any` return signature would be wrong here, but a `nothing -> any` one is
# fine: `drive` is what may throw, and it does so through the guard below.
# IT TAKES NO RECORDS. It reads the store itself, on every frame — because the
# list is LIVE, so a snapshot handed in at the door would be discarded before the
# first repaint and the parameter would be a lie.
export def choose [
    --query: string = ""        # prefills the filter
    --table: record             # override the locator table (tests)
]: nothing -> any {

    # The terminal's modes are BORROWED, and giving them back must not depend on
    # finishing normally. Nothing is done inside the catch but reading `$e.msg`,
    # because an error raised in a catch block escapes it — and nushell then
    # reports the ORIGINAL error at the ORIGINAL span, so it looks exactly like a
    # `try` that does not work (§10).
    print -n (tty setup)
    let r = try {
        {ok: true, picked: (drive $query $table)}
    } catch {|e| {ok: false, why: $e.msg} }
    print -n (tty restore)

    if not $r.ok { error make --unspanned {msg: $r.why} }
    $r.picked
}
