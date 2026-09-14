# Which integration an agent RUNS INSIDE, and how to get to it.
#
# THE SAME IDEA AS `core/dispatch.nu`'s `integration-registry`, for the other
# capability an integration can have (plan.md §4.8, D69). A hand-written table
# of closures, because nushell has no first-class modules and a name cannot be
# turned into one at runtime (D26). Adding tmux is one file and one row here.
#
# THREE QUESTIONS, and it was four until step 8. `screen` — dump me this agent's
# live terminal — went with the preview that needed it (D58): what the picker
# shows is the stored message now, which every record has and no tool has to be
# asked for. A container answers only what the multiplexer alone can answer.
#
# ── IT USED TO LIVE IN `picker/`, AND THAT WAS THE BUG (D70) ──────────────────
# Not one of the three questions is the picker's. What was the picker's is only
# that it asked them first — so this was a CONTRACT filed inside its first
# consumer, which the second consumer makes untenable: a click on a bar row
# would have had to reach through the picker to find out where an agent lives.
# It is `integrations/` because that is where the tools answering it are.
#
# ── IT IS A SEPARATE TABLE FROM THE DISPLAYS, ON PURPOSE (D71) ────────────────
# One table with optional members would make adding an integration one edit
# instead of two, and it would be wrong: such a table `use`s both halves of
# every tool, so `core/dispatch.nu` — which every hook imports — would reach
# `jump.nu`, and through it `core/session-store.nu` and `core/config.nu`, by a
# SECOND import path. A module reached twice is parsed twice, on every event,
# forever (§10 measured that diamond at 4.51ms against 3.57ms).
#
# So the rule a third capability will follow: A REGISTRY LIVES WHERE ITS
# CONSUMERS CAN REACH IT AND NO DISPLAY CAN. This one's consumers are
# `cli/jump.nu`, `cli/browse.nu` and `picker/rows.nu`; no display and therefore
# no hook is among them.
#
# ── THE RECORD PICKS ITS OWN CONTAINER ────────────────────────────────────────
# Not the config file. `displays:` says what the store is PUSHED to and nothing
# else (D47), so it must not decide where a caller can TAKE you — switching the
# zellij display off means "stop renaming my panes", not "stop jumping to them".
#
# So the question is asked of the RECORD: an agent carrying a `zellij` namespace
# is placed and reached through zellij, one carrying `tmux` through tmux, one
# carrying neither is still a row — just one with no place and nowhere to go.
# That is the open session-schema (D11c) doing the dispatching for free, and it
# means a MIXED fleet works with nothing configured.
#
# ORDER IS THE TIE-BREAK, and it is the order written below. An agent reporting
# two namespaces is not a thing today; when it is, first-listed wins, which is
# at least stable.

# A HYPHEN IN A MODULE NAME BECOMES AN UNDERSCORE IN ITS CONSTANT (§10).
# `use zellij/session-container.nu` makes the module addressable as
# `session-container` in COMMAND position and as `$session_container` in
# VARIABLE position — which is where `INFO` lives. Spelled the obvious way it is
# a parse error about a variable name, some distance from the cause.
use zellij/session-container.nu

# One entry per integration that can answer the three questions. `info` is here
# for the same reason a display has one: something has to be able to say what
# exists without running any of it.
export def integration-registry []: nothing -> record {
    { zellij: {info: $session_container.INFO
               owns-session: {|rec| session-container owns-session $rec }
               location-label: {|rec| session-container location-label $rec }
               focus-session: {|rec| session-container focus-session $rec }} }
}

export def integration-registry-names []: nothing -> list<string> { integration-registry | columns }

# The container that claims this session, or null when none does.
#
# `--table` is how the suite runs the whole picker with nothing installed: a
# fake container answers the three questions out of a record, the same move
# `tests/fake.nu` makes for the display contract.
export def container-of [rec: record, --table: record]: nothing -> any {
    let t = $table | default (integration-registry)
    for name in ($t | columns) {
        let c = $t | get $name
        let mine = try { do $c.owns-session $rec } catch { false }
        if $mine { return $c }
    }
    null
}
