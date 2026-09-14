# Focus an agent's pane — zellij's half of `focus-session`.
#
# The PULL half of the zellij integration. Nothing dispatches to it and nothing
# in `displays:` turns it on: it runs because you ran it (plan.md D47). It is no
# longer the `agent-notify jump` COMMAND — that is `cli/jump.nu`, which asks the
# registry which container has the agent (D75). This is one container's answer,
# and it is what both the picker and a click on a bar row end up in.
#
# IT TAKES A RECORD, NOT A NAME. Resolving a name is `core/find-session.nu`'s
# job and never was zellij's; the caller has already done it, and asking twice
# would be two reads of the session-store for one jump.
#
# `argv` RETURNS A LIST OF COMMANDS, not one. Today it is always a single focus.
# The shape is kept because a session is not inside ONE container — it is at a
# path through several, and reaching it is each of them focusing its own
# coordinate in turn (D77, step 12). A shape that can only hold one command
# would have to be broken to say that.
#
# THREE THINGS ZELLIJ DOES THAT THE CODE HAS TO KNOW. All three were probed
# rather than assumed, and all three can turn a jump into a silent no-op:
#
#   1. IT EXITS 0 WHETHER OR NOT IT WORKED. "Pane with id Terminal(99999) not
#      found" comes back on STDERR with an exit code of zero, so the exit code
#      says nothing at all and stderr is the whole answer. (Same shape as macOS
#      `ps` — plan.md §11.) And stderr is not only used for failures: asking for
#      the pane you are already in answers "Pane Terminal(3) is already focused",
#      which is a jump that succeeded. So the BENIGN messages are named and
#      everything else is raised — the other way round would make a real failure
#      silent, which is what this whole note exists to prevent.
#
#   2. `switch-session` CREATES A SESSION IT CANNOT FIND. A record naming a
#      session that has since been killed would not fail: it would spawn an empty
#      one and take you there. So a switch checks `list-sessions` first. Found by
#      probing — it left an orphan server behind. `focus-pane-id` needs no such
#      guard, which is why the check is not paid for on the common path: a session
#      that is gone answers "Session 'X' not found" and rule 1 raises it.
#
#   3. A PANE IS `terminal_7` HERE AND `7` THERE. `focus-pane-id` takes either
#      spelling; `switch-session --pane-id` takes only the long one. The store
#      holds the short one, so the conversion lives in one place below.
#
# WHAT IS DELIBERATELY NOT HERE: any window manager, and no setting naming one
# either. Bringing the terminal's WINDOW forward is not a special case of this
# file — it is a different container, one level out, answering the same three
# questions about its own coordinate (D77). A `focus_terminal_window:` argv
# briefly lived here and was unwound: it flattened a real structure into a
# string on the wrong tool, and it made the outermost container something you
# configure rather than something you have. See plan.md step 12.
#
# So zellij focuses a pane, and nothing else, and that stays true however many
# containers end up outside it. v1 did the opposite — it called aerospace, fell
# back to `open -a Ghostty`, and read the attached session out of the terminal's
# WINDOW TITLE; running inside zellij makes that last one a lookup of
# `$env.ZELLIJ_SESSION_NAME`.

use ../../core/config.nu
use program.nu

# What zellij says on stderr that does NOT mean the jump failed — see note 1.
const BENIGN = ["already focused"]

# The `commands` half of this tool's namespace, plus what it shares with the
# display half — which today is the whole of it.
def settings []: nothing -> record {
    let given = config settings-for (config load) "zellij" "commands"
    {binary: (program resolve ($given.binary? | default ""))}
}

# See note 3.
def pane-ref [id: string]: nothing -> string {
    if ($id | str starts-with "terminal_") { $id } else { $"terminal_($id)" }
}

# Every session zellij currently has — see note 2. Empty when it cannot be
# asked, which reads as "do not switch": refusing to move is recoverable, and
# creating a session nobody asked for is not.
def sessions [binary: string]: nothing -> list<string> {
    let r = try { ^$binary list-sessions --short --no-formatting | complete } catch { null }
    if ($r == null) { return [] }
    $r.stdout | lines | each {|l| $l | str trim } | where {|l| $l | is-not-empty }
}

# THE WHOLE DECISION, as DATA — the same split `mod.nu`'s `commands` and the
# bar's `message` use, and here it earns its keep twice over: the cross-session
# branch moves your screen to another session, which is not something a test
# suite may do, and `agent-notify jump --dry-run` answers "what would that
# actually run?" without running it.
#
# Being outside zellij (`here` empty) reads as "tell the target session to move
# whatever client it has" — the best available without a window in front of it.
export def argv [
    rec: record     # the session to focus, already resolved
] {
    let z = $rec.zellij? | default {}
    let session = $z.session? | default ""
    let pane = $z.pane_id? | default ""
    let label = $rec.name? | default $rec.id

    if ($session | is-empty) or ($pane | is-empty) {
        error make --unspanned {msg: ($"agent-notify: '($label)' is not in a zellij pane — "
            + "nothing to jump to")}
    }

    let binary = (settings).binary
    let here = $env.ZELLIJ_SESSION_NAME? | default ""
    if ($here == $session) or ($here | is-empty) {
        return [[$binary "--session" $session "action" "focus-pane-id" (pane-ref $pane)]]
    }

    # Only now, and only here — see note 2.
    if ($session not-in (sessions $binary)) {
        error make --unspanned {msg: ($"agent-notify: zellij has no session called '($session)', "
            + $"which is where '($label)' says it is")}
    }
    [[$binary "--session" $here "action" "switch-session" $session "--pane-id" (pane-ref $pane)]]
}

# Focus the agent's pane, switching session first when it lives in another one.
#
# Silent on success, the way a command that moved your screen should be: you are
# looking at the result.
export def main [
    rec: record     # the session to focus, already resolved
] {
    for cmd in (argv $rec) {
        let r = ^($cmd | first) ...($cmd | skip 1) | complete
        let why = $r.stderr | str trim
        if ($why | is-empty) { continue }
        if ($BENIGN | any {|b| $why | str contains $b }) { continue }
        error make --unspanned {msg: $"agent-notify: ($why)"}
    }
}
