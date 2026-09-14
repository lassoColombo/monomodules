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
# `argv` RETURNS A LIST OF COMMANDS, not one. Today it is always a single
# focus — but a caller arriving from the desktop has a window to focus first
# (D73), and a shape that can only hold one command would have to be broken to
# say so.
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
# ── TWO LEVELS OF "GO THERE", AND ONLY ONE OF THEM IS ZELLIJ'S ────────────────
# A pane is inside a terminal; the terminal is inside a window; which window is
# in FRONT is the operating system's business. Focusing pane 7 is correct and
# changes nothing on your screen if you are looking at another application. So
# the ladder is: focus the terminal's WINDOW, then focus the SESSION inside it.
#
# WHO CLIMBS IT IS DECIDED HERE, not by the caller (D73). The question is only
# "are we inside zellij right now", which `$env.ZELLIJ_SESSION_NAME` answers for
# free and which this file was already branching on:
#
#   inside zellij, same session       focus the pane
#   inside zellij, another session    switch, which focuses the pane
#   NOT INSIDE ZELLIJ AT ALL          focus the window FIRST, then the pane
#
# The picker is always the first two — it runs in the terminal, so the first
# rung was climbed by hand when you typed. A click on a bar row is the third,
# and it is the only caller that has ever needed the window.
#
# A flag would have been the wrong shape: `--from-desktop` makes every future
# caller work out something about itself that this file can simply look up, and
# it would be wrong in the first place somebody copied it.
#
# WHAT THE WINDOW COMMAND IS, WE DO NOT KNOW AND WILL NOT GUESS (D50, D74). It
# is `zellij.commands.focus_terminal_window:` — argv the user writes, because
# which program brings a terminal forward depends on their terminal and their
# window manager. What that looks like, for the two shapes it usually takes:
#
#   focus_terminal_window: [/usr/bin/open, -a, Ghostty]        # the terminal
#   focus_terminal_window: [/opt/homebrew/bin/aerospace, focus-monitor, …]
#
# The first is the safe one and works without a window manager at all. Empty by default, which is not a fallback but the honest
# answer: with nothing configured this file behaves exactly as it did before the
# rung existed. v1 guessed, called aerospace, fell back to `open -a Ghostty`,
# and read the attached session out of the terminal's WINDOW TITLE besides.

use ../../core/config.nu
use program.nu

# What zellij says on stderr that does NOT mean the jump failed — see note 1.
const BENIGN = ["already focused"]

# The `commands` half of this tool's namespace, plus what it shares with the
# display half.
#
# Strict about `focus_terminal_window` because the failure it prevents is
# SILENT: a bar click runs under launchd, whose PATH is /usr/bin:/bin and
# nothing else, so a bare `aerospace` there is not a command that fails — it is
# a command that does not exist, on a path nobody is watching. The first element
# is resolved the way `binary` is, and for the same reason (§11).
#
# PURE, and exported, for the same reason a display's `settings` is: only the
# tool knows what its keys mean, so `agent-notify config check` has to be able
# to ask. Unlike a display's, it is checked WHETHER OR NOT the tool is in
# `displays:` — nothing turns commands on, so a typo here is always live.
#
# No return-type signature: a def annotated with one cannot END in `error make`
# (plan.md §10).
export def commands-settings [given: record] {
    for k in ($given | columns | where {|k| $k not-in ["binary" "focus_terminal_window"] }) {
        error make --unspanned {msg: ($"zellij: '($k)' is not a command setting "
            + "\(try: binary, focus_terminal_window\)")}
    }
    { binary: (program resolve ($given.binary? | default ""))
      focus_terminal_window: (window-argv ($given.focus_terminal_window? | default [])) }
}

def settings [] { commands-settings (config settings-for (config load) "zellij" "commands") }

# An empty list means "do not climb", which is the default and is not an error:
# with nothing configured a jump does exactly what it did before there was a
# rung to climb.
def window-argv [given: any] {
    if ($given == null) or ($given == []) { return [] }
    if not (($given | describe) | str starts-with "list") {
        error make --unspanned {msg: ($"zellij: `commands.focus_terminal_window` must be a list of "
            + $"arguments, got ($given | describe) \(try: [open, -a, Ghostty])")}
    }
    let parts = $given | each {|a| $a | into string }
    if ($parts | any {|a| ($a | str trim) | is-empty }) {
        error make --unspanned {msg: "zellij: `commands.focus_terminal_window` has an empty argument"}
    }
    let head = $parts | first
    if ($head | str starts-with "/") {
        if not ($head | path exists) {
            error make --unspanned {msg: $"zellij: no program at '($head)' \(commands.focus_terminal_window)"}
        }
        return $parts
    }
    let found = which $head | get -o 0.path | default ""
    if ($found | is-empty) {
        error make --unspanned {msg: ($"zellij: `commands.focus_terminal_window` names '($head)', which "
            + "is not on PATH — give its absolute path, because a bar click runs with launchd's PATH "
            + "and not your shell's")}
    }
    [$found] ++ ($parts | skip 1)
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

    let cfg = settings
    let binary = $cfg.binary
    let here = $env.ZELLIJ_SESSION_NAME? | default ""

    # The first rung, and only when we are not on the ladder already — see the
    # header. Inside zellij by any route, the window is in front by definition.
    let window = if ($here | is-empty) and ($cfg.focus_terminal_window | is-not-empty) {
        [$cfg.focus_terminal_window]
    } else { [] }

    if ($here == $session) or ($here | is-empty) {
        return ($window ++ [[$binary "--session" $session "action" "focus-pane-id" (pane-ref $pane)]])
    }

    # Only now, and only here — see note 2.
    if ($session not-in (sessions $binary)) {
        error make --unspanned {msg: ($"agent-notify: zellij has no session called '($session)', "
            + $"which is where '($label)' says it is")}
    }
    $window ++ [[$binary "--session" $here "action" "switch-session" $session "--pane-id" (pane-ref $pane)]]
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
