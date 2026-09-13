# Which integration can show an agent, and take you to it.
#
# THE SAME IDEA AS `core/dispatch.nu`'s `shipped`, one directory down and for the
# other half of an integration. A hand-written table of closures, because nushell
# has no first-class modules and a name cannot be turned into one at runtime
# (D26). Adding tmux is one file and one row here.
#
# THREE QUESTIONS, and it was four until step 8. `screen` — dump me this agent's
# live terminal — went with the preview that needed it (D58): what the picker
# shows is the stored message now, which every record has and no tool has to be
# asked for. A locator is down to what only the multiplexer can answer.
#
# ── THE RECORD PICKS ITS OWN LOCATOR ─────────────────────────────────────────
# Not the config file. `surfaces:` says what the store is PUSHED to and nothing
# else (D47), so it must not decide where the picker can TAKE you — switching the
# zellij surface off means "stop renaming my panes", not "stop jumping to them".
#
# So the question is asked of the RECORD: an agent carrying a `zellij` namespace
# is placed and reached through zellij, one carrying `tmux` through tmux, one
# carrying neither is still a row — just one with no place and nowhere to go.
# That is the open schema (D11c) doing the dispatching for free, and it means a
# MIXED fleet works with nothing configured.
#
# ORDER IS THE TIE-BREAK, and it is the order written below. An agent reporting
# two namespaces is not a thing today; when it is, first-listed wins, which is at
# least stable.

use ../integrations/zellij/locate.nu

# One entry per integration that can answer the three questions. `info` is here
# for the same reason a surface has one: something has to be able to say what
# exists without running any of it.
export def shipped []: nothing -> record {
    { zellij: {info: $locate.INFO
               claims: {|rec| locate claims $rec }
               place:  {|rec| locate place $rec }
               go:     {|rec| locate go $rec }} }
}

export def known []: nothing -> list<string> { shipped | columns }

# The locator that claims this record, or null when none does.
#
# `--table` is how the suite runs the whole picker with nothing installed: a fake
# locator answers the three questions out of a record, the same move `tests/fake.nu`
# makes for the surface contract.
export def owner [rec: record, --table: record]: nothing -> any {
    let t = $table | default (shipped)
    for name in ($t | columns) {
        let l = $t | get $name
        let mine = try { do $l.claims $rec } catch { false }
        if $mine { return $l }
    }
    null
}
