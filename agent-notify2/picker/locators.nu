# Which integration can show an agent, and take you to it.
#
# THE SAME IDEA AS `core/dispatch.nu`'s `shipped`, one directory down and for the
# other half of an integration. A hand-written table of closures, because nushell
# has no first-class modules and a name cannot be turned into one at runtime
# (D26). Adding tmux is one file and one row here.
#
# ── THE RECORD PICKS ITS OWN LOCATOR ─────────────────────────────────────────
# Not the config file. `surfaces:` says what the store is PUSHED to and nothing
# else (D47), so it must not decide what the picker can SHOW — switching the
# zellij surface off means "stop renaming my panes", not "stop previewing them".
#
# So the question is asked of the RECORD: an agent carrying a `zellij` namespace
# is previewed through zellij, one carrying `tmux` through tmux, one carrying
# neither falls back to what every record has — its stored message. That is the
# open schema (D11c) doing the dispatching for free, and it means a MIXED fleet
# works with nothing configured.
#
# ORDER IS THE TIE-BREAK, and it is the order written below. An agent reporting
# two namespaces is not a thing today; when it is, first-listed wins, which is at
# least stable.

use ../integrations/zellij/locate.nu

# One entry per integration that can answer the four questions. `info` is here
# for the same reason a surface has one: something has to be able to say what
# exists without running any of it.
export def shipped []: nothing -> record {
    { zellij: {info: $locate.INFO
               claims: {|rec| locate claims $rec }
               place:  {|rec| locate place $rec }
               screen: {|rec, n| locate screen $rec $n }
               go:     {|rec| locate go $rec }} }
}

export def known []: nothing -> list<string> { shipped | columns }

# The locator that claims this record, or null when none does.
#
# `--table` is how the suite runs the whole picker with nothing installed: a fake
# locator answers the four questions out of a record, the same move `tests/fake.nu`
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
