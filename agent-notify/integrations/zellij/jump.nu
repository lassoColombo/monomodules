# `agent-notify jump <who>` — go to an agent's pane.
#
# The PULL half of the zellij integration. Nothing dispatches to it and nothing
# in `surfaces:` turns it on: it runs because you ran it (plan.md D47). The
# picker's last line is a call to this, and a click on a bar row will be too.
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
# WHAT IS DELIBERATELY NOT HERE: any window manager. Raising the terminal's window
# is a different problem with a different caller — the picker runs INSIDE the
# terminal, where the window is already in front, and a bar click is the only case
# that needs it. Leaving it until the click is built is what keeps this file from
# naming a program we do not ship or assuming an operating system. v1 did both,
# and read the attached session out of the terminal's WINDOW TITLE besides;
# running inside zellij makes that a lookup of `$env.ZELLIJ_SESSION_NAME`.

use ../../core/store.nu
use ../../core/config.nu
use program.nu

# What zellij says on stderr that does NOT mean the jump failed — see note 1.
const BENIGN = ["already focused"]

# The `commands` half of this tool's namespace, plus what it shares with the
# surface half — which today is the whole of it.
def settings []: nothing -> record {
    let given = config section (config load) "zellij" "commands"
    {binary: (program resolve ($given.binary? | default ""))}
}

# See note 3.
def pane-ref [id: string]: nothing -> string {
    if ($id | str starts-with "terminal_") { $id } else { $"terminal_($id)" }
}

# Every session zellij currently has — see note 2. Empty when it cannot be asked,
# which reads as "do not switch": refusing to move is recoverable, and creating a
# session nobody asked for is not.
def sessions [binary: string]: nothing -> list<string> {
    let r = try { ^$binary list-sessions --short --no-formatting | complete } catch { null }
    if ($r == null) { return [] }
    $r.stdout | lines | each {|l| $l | str trim } | where {|l| $l | is-not-empty }
}

# Which agent you meant. An id is a uuid, which nobody types, so a unique PREFIX
# of one works — and so does an agent's NAME, which is the thing the naming
# convention exists to give it. Ambiguity is an error that lists the candidates
# rather than a coin toss.
#
# No return-type signature: a def annotated with one cannot END in `error make`
# (plan.md §10). Same for `argv` below.
@search-terms agent notify jump find which resolve id name prefix
@example "which agent does this prefix mean?" { agent-notify jump find 6923c0 }
export def find [
    who: string     # an agent's id, a unique prefix of one, or its name
] {
    let all = store list
    let exact = $all | where {|r| ($r.id? | default "") == $who }
    if ($exact | is-not-empty) { return ($exact | first) }

    let byname = $all | where {|r| ($r.name? | default "") == $who }
    let prefix = $all | where {|r| ($r.id? | default "") | str starts-with $who }
    let hits = ($byname ++ $prefix) | uniq-by id
    if ($hits | length) == 1 { return ($hits | first) }
    if ($hits | is-empty) {
        error make --unspanned {msg: $"agent-notify: no agent called '($who)' \(try: agent-notify store list\)"}
    }
    let which = $hits | each {|r| $"($r.id) \(($r.name? | default '-')\)" } | str join ", "
    error make --unspanned {msg: $"agent-notify: '($who)' could be any of: ($which)"}
}

# THE WHOLE DECISION, as DATA — the same split `mod.nu`'s `commands` and the
# bar's `message` use, and here it earns its keep twice over: the cross-session
# branch moves your screen to another session, which is not something a test
# suite may do, and `agent-notify jump argv <who>` answers "what would that
# actually run?" without running it.
#
# Being outside zellij (`here` empty) reads as "tell the target session to move
# whatever client it has" — the best available without a window to raise.
@search-terms agent notify jump argv dry run command preview what would
@example "what would that do?" { agent-notify jump argv build-the-thing }
export def argv [
    who: string     # an agent's id, a unique prefix of one, or its name
] {
    let rec = find $who
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
        return [$binary "--session" $session "action" "focus-pane-id" (pane-ref $pane)]
    }

    # Only now, and only here — see note 2.
    if ($session not-in (sessions $binary)) {
        error make --unspanned {msg: ($"agent-notify: zellij has no session called '($session)', "
            + $"which is where '($label)' says it is")}
    }
    [$binary "--session" $here "action" "switch-session" $session "--pane-id" (pane-ref $pane)]
}

# Focus the agent's pane, switching session first when it lives in another one.
#
# Silent on success, the way a command that moved your screen should be: you are
# looking at the result.
@search-terms agent notify jump go focus goto pane session zellij attach switch
@example "go to an agent by name" { agent-notify jump build-the-thing }
@example "…or by the start of its id" { agent-notify jump 6923c0bc }
export def main [
    who: string     # an agent's id, a unique prefix of one, or its name
] {
    let cmd = argv $who
    let r = ^($cmd | first) ...($cmd | skip 1) | complete
    let why = $r.stderr | str trim
    if ($why | is-empty) { return }
    if ($BENIGN | any {|b| $why | str contains $b }) { return }
    error make --unspanned {msg: $"agent-notify: ($why)"}
}
