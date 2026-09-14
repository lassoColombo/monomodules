# Which integration an agent RUNS INSIDE, and how to get to it.
#
# THE SAME IDEA AS `core/dispatch.nu`'s `integration-registry`, for the other
# capability an integration can have (plan.md §4.8, D70). A hand-written table
# of closures, because nushell has no first-class modules and a name cannot be
# turned into one at runtime (D26). Adding tmux is one file and one row here.
#
# FOUR MEMBERS, THREE QUESTIONS — `focus-session` has a data half in front of
# it, `focus-session-argv`, so a jump can be asserted without moving a screen.
# And it was four questions until step 8. `screen` — dump me this agent's
# live terminal — went with the preview that needed it (D58): what the picker
# shows is the stored message now, which every record has and no tool has to be
# asked for. A container answers only what the multiplexer alone can answer.
#
# ── IT USED TO LIVE IN `picker/`, AND THAT WAS THE BUG (D71) ──────────────────
# Not one of the three questions is the picker's. What was the picker's is only
# that it asked them first — so this was a CONTRACT filed inside its first
# consumer, which the second consumer makes untenable: a click on a bar row
# would have had to reach through the picker to find out where an agent lives.
# It is `integrations/` because that is where the tools answering it are.
#
# ── IT IS A SEPARATE TABLE FROM THE DISPLAYS, ON PURPOSE (D72) ────────────────
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
# ── ORDER IS NESTING ORDER, AND IT IS THE ORDER WRITTEN BELOW (D78) ───────────
# A session is not inside ONE container. It is at a PATH through several (D77):
#
#     aerospace  ──▶  Ghostty  ──▶  zellij  ──▶  pane 7
#     workspace 1     window 39     home/root
#
# so `containers-of` returns EVERY container that claims a record, and reaching
# the agent is each of them focusing its own coordinate in turn, outside in.
# Read this file's table top to bottom and you are reading outside to inside.
#
# There is no taxonomy to derive that order from and there is not going to be
# one: a window-manager/application/multiplexer vocabulary was drafted and cut,
# because the list already says it and naming the kinds named nothing (D78).
# Adding tmux is one file and one row, placed where it nests.
#
# What the single list assumes is that nesting order is the same for everyone,
# which holds for the real case — a window manager is never inside a
# multiplexer. Where it would not hold is zellij inside tmux inside zellij, and
# one list can spell only one order. Written down as the limit rather than
# designed around.
#
# ── `owns-session` AND `location-label` MUST NOT TOUCH THE WORLD ──────────────
# The picker calls both FOR EVERY RECORD, every two seconds and on every
# keypress (`picker/mod.nu`, REFRESH_EVERY). A container that answered either by
# running a program would put one subprocess per agent on a 2-second timer.
#
# So the rule is: the two cheap questions are answered FROM THE RECORD, and a
# container that can only find out by asking the world claims OPTIMISTICALLY and
# discovers at jump time — where a subprocess is already being run and a human
# is already waiting. `focus-session-argv` is the member allowed to look.

# A HYPHEN IN A MODULE NAME BECOMES AN UNDERSCORE IN ITS CONSTANT (§10).
# `use zellij/session-container.nu` makes the module addressable as
# `session-container` in COMMAND position and as `$session_container` in
# VARIABLE position — which is where `INFO` lives. Spelled the obvious way it is
# a parse error about a variable name, some distance from the cause.
use zellij/session-container.nu

# One entry per integration that can answer them. `info` is here
# for the same reason a display has one: something has to be able to say what
# exists without running any of it.
export def integration-registry []: nothing -> record {
    { zellij: {info: $session_container.INFO
               owns-session: {|rec| session-container owns-session $rec }
               location-label: {|rec| session-container location-label $rec }
               focus-session-argv: {|rec| session-container focus-session-argv $rec }
               focus-session: {|rec| session-container focus-session $rec }} }
}

export def integration-registry-names []: nothing -> list<string> { integration-registry | columns }

# Every container that claims this session, outermost first. Empty when none
# does, which is an ordinary answer: an agent nothing contains is still a row in
# the picker — just one with no place and nowhere to go.
#
# `--table` is how the suite runs the whole picker with nothing installed: fake
# containers answer out of a record, the same move `tests/fake.nu` makes for the
# display contract.
export def containers-of [rec: record, --table: record]: nothing -> list<record> {
    let t = $table | default (integration-registry)
    $t | columns | each {|name|
        let c = $t | get $name
        let mine = try { do $c.owns-session $rec } catch { false }
        if $mine { $c } else { null }
    } | where {|c| $c != null }
}

# Where the session lives, as a path — each container's own label, outside in,
# joined. A container with nothing worth a column says "" and drops out, so a
# chain of three can still read as one word.
export def location-label [rec: record, --table: record]: nothing -> string {
    containers-of $rec --table ($table | default (integration-registry))
    | each {|c| try { do $c.location-label $rec } catch { "" } }
    | where {|l| $l | is-not-empty }
    | str join "/"
}

# PURE: every command reaching this session would run, outermost first. This is
# what `agent-notify jump --dry-run` prints, and it is the whole decision as
# data — the same split `render-items`/`push-items` make for a display.
#
# A container that claims a session but cannot work out how to reach it right
# now returns nothing and drops out, rather than failing the whole path: it is
# the OUTER rungs that are uncertain, and not climbing one is worth less than
# not arriving at all.
export def focus-session-argv [rec: record, --table: record]: nothing -> list<list<string>> {
    containers-of $rec --table ($table | default (integration-registry))
    | each {|c| try { do $c.focus-session-argv $rec } catch { [] } }
    | flatten
}

# Walk the path, outside in. Each container runs its OWN commands rather than
# this walking a flattened argv, because what a command's failure MEANS is the
# container's to know — zellij's "already focused" is a success, and nothing out
# here could tell that from a real failure (plan.md §11).
#
# IT STOPS AT THE FIRST FAILURE. A rung that fails is a rung you are standing
# below, so the ones inside it would be focusing something you cannot see:
# arriving half way and saying nothing about it is worse than not arriving and
# saying so. The error names the container, because "the jump failed" is not
# actionable and "aerospace failed" is.
#
# A container that CANNOT REACH is not a failure and does not stop anything — it
# contributes no commands and the walk carries on past it (see
# `focus-session-argv`). The two are different answers: *I have nothing to do*
# and *I tried and could not*.
export def focus-session [rec: record, --table: record]: nothing -> nothing {
    for c in (containers-of $rec --table ($table | default (integration-registry))) {
        try { do $c.focus-session $rec } catch {|e|
            error make --unspanned {msg: $"agent-notify: ($c.info.name): ($e.msg)"}
        }
    }
}
