# Which agent you meant.
#
# An id is a uuid, which nobody types, so a unique PREFIX of one works — and so
# does an agent's NAME, which is the thing the naming convention exists to give
# it. Ambiguity is an error that lists the candidates rather than a coin toss.
#
# IN `core/` BECAUSE IT IS A QUESTION ABOUT THE SESSION-STORE, not about zellij.
# It lived in `integrations/zellij/jump.nu` for as long as the jump was zellij's
# command (D74), which made it look like a zellij idea; it never was. It is COLD
# — no display and no hook reaches it, only `cli/jump.nu` — so it costs the
# event path nothing.

use session-store.nu

# No return-type signature: a def annotated with one cannot END in `error make`
# (plan.md §10).
@search-terms agent notify find session which resolve id name prefix
@example "which agent does this prefix mean?" { find-session 6923c0 }
export def main [
    who: string     # an agent's id, a unique prefix of one, or its name
] {
    let all = session-store list
    let exact = $all | where {|r| ($r.id? | default "") == $who }
    if ($exact | is-not-empty) { return ($exact | first) }

    let byname = $all | where {|r| ($r.name? | default "") == $who }
    let prefix = $all | where {|r| ($r.id? | default "") | str starts-with $who }
    let hits = ($byname ++ $prefix) | uniq-by id
    if ($hits | length) == 1 { return ($hits | first) }
    if ($hits | is-empty) {
        error make --unspanned {msg: $"agent-notify: no agent called '($who)' \(try: agent-notify session-store list\)"}
    }
    let which = $hits | each {|r| $"($r.id) \(($r.name? | default '-')\)" } | str join ", "
    error make --unspanned {msg: $"agent-notify: '($who)' could be any of: ($which)"}
}
