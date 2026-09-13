# The picker: a list of agents, a live preview of the one under the cursor, and
# the id of whichever you chose.
#
# THE ONLY IMPURE FILE IN THIS DIRECTORY. Three calls touch the world — read the
# store, print, read a key — and everything between them is a pure function
# living in `rows.nu`, `frame.nu`, `preview.nu` or `keys.nu`, each with its own
# assertions. That is deliberate: an event loop is the one part a suite cannot
# drive, so it is kept to the three lines that must be here.
#
# It was FOUR until step 8. The preview used to dump the agent's real terminal,
# which is a subprocess per frame and the one part of a frame the suite could not
# assert; it is the stored message now (D58), so that call went and took the
# whole of `preview-of` out of this file with it.
#
#   loop {
#       records ← the store          re-read EVERY frame: 0.33ms, so the list is live
#       rows    ← build, narrow      pure
#       view    ← settle             pure: the selection still exists? scrolled?
#       preview ← the message        pure: markdown flattened, cut to the pane
#       lines   ← render             pure: the whole screen, as strings
#       print IF THE FRAME MOVED     unchanged ⇒ not one byte
#       key     ← input listen       blocks; beats every 2s so the list stays live
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
# `--timeout` makes a quiet moment into a redraw, which is what keeps the LIST
# live while you sit still — an agent changing state re-sorts it, and a message
# that lands while you are reading replaces the preview. nushell delivers that
# expiry as an ERROR rather than as a null, so it has to be caught.
#
# And catching it is exactly where a picker can be made to spin. `catch { null }`
# reads "there is no terminal" the same way it reads "nothing happened", so with
# stdin closed the loop turns over about 37,000 times a second forever — and back
# when a frame dumped a pane, each of those passes spawned a zellij client too.
# Measured. So the catch is TIMED instead: a timeout that did not take the
# timeout's worth of time was not a timeout.
#
# Timed rather than matched on the message text, because the wording belongs to
# nushell and a reworded error would otherwise mean the picker exits instantly on
# every heartbeat.

use ../core/store.nu
use rows.nu
use frame.nu
use preview.nu
use keys.nu
use tty.nu

# Long enough that a quiet picker is nearly free — one 0.33ms store read per 2s,
# now that no frame spawns anything — and short enough that an agent changing
# state, or finally answering, shows up while you are still looking at it.
const BEAT = 2sec

# Under this, the listen cannot have waited out the beat — so it failed for some
# other reason, and the only one that matters is "there is no terminal here".
const QUICK = 200ms

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

        let seen = preview of (rows selected $shown $view) $lay.preview $lay.width
        let lines = frame render $shown $view $lay $seen
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
                    + "or bind it to a floating pane with `agent-notify browse wiring`")}
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
