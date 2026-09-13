# Filing away records for agents that are gone.
#
# `SessionEnd` files a session away when it exits cleanly, so the only leaks
# come from agents that never got to say goodbye: a killed process, a crash, a
# closed pane, a closed terminal. This is where those are cleaned up, and
# `core/proc.nu` is what makes it possible to do so on PROOF rather than on a
# hunch.
#
# THE SAME GESTURE AS A CLEAN EXIT. These are archived, not deleted
# (core/session-store.nu `end-session`): an agent that was killed is no less
# resumable than one that was quit, and its name is no less worth keeping.
#
# TWO RULES, and the second one is the safety rail:
#
#   the recorded process is gone          →  file it away
#   we cannot tell, for any reason        →  touch nothing
#
# "Cannot tell" covers a record with no `proc` at all (its SessionStart happened
# before this existed, or its agent could not be located) and a `ps` that failed
# to answer. Not knowing must never become deleting: one unreadable answer would
# otherwise wipe every live agent in the session-store.
#
# ONE EXTRA CASE. `/clear` does not end the process — the same agent starts a
# fresh session inside it. So two records can name one pid that is genuinely
# alive, and the older of them is finished. A process runs one session at a
# time, so among records sharing a live pid only the most recently updated
# survives.
#
# NEVER ON A HOOK. `ps` costs ~13ms and there is nothing a hook could do with
# the answer. It runs from `agent-notify session-store sweep`, from `displays
# refresh` (so the bar's timer pays for it in step 5), and from the picker
# before it lists.

use session-store.nu
use proc.nu

# Drop what is provably gone; return what was dropped, and why.
export def sweep-dead-sessions []: nothing -> table {
    let tracked = session-store list | where {|r| ($r.proc?.pid? | default 0) > 0 }
    if ($tracked | is-empty) { return [] }

    let living = proc living ($tracked | get proc)
    if $living == null { return [] }

    let gone = $tracked | where {|r| $r.proc.pid not-in $living }
    let here = $tracked | where {|r| $r.proc.pid in $living }

    # Sharing a live pid: the newest is the session actually running in it.
    let superseded = $here | where {|r|
        # Bound rather than written as one long `and` chain: a boolean
        # expression does not continue across lines with the operator at either
        # end (§10).
        let rivals = $here | where {|o| ($o.id != $r.id) and ($o.proc.pid == $r.proc.pid) }
        $rivals | any {|o| $o.updated_at > $r.updated_at }
    }

    let doomed = $gone ++ $superseded
    for d in $doomed { session-store end-session $d.id | ignore }
    # The WHOLE record, not a summary: a display has to be told what vanished in
    # order to undo it — a pane cannot be handed back by its id alone.
    $doomed | each {|d|
        $d | merge {why: (if ($d.proc.pid in $living) {
            "superseded — /clear left it behind"
        } else { "process gone" })}
    }
}
