# Step 6 — `agent-notify2 browse`: the rows, and what the pane shows.
#
# The picker itself cannot be driven from here — skim needs a terminal, and
# without one it fails with "Operation not supported on socket". So the file is
# split the way every other side effect in this module is: `rows` and `preview`
# are pure functions of records, asserted exactly, and `main` is the dozen lines
# that hand them to skim. (Verified once by hand in a real floating pane, with
# `--select-1`, which is the only way to prove the flags are all valid.)
#
# Colours come off before comparing. They are real — a state is legible at a
# glance because of them — but they are also the one thing a test should not
# freeze, since they follow the terminal's theme.

use ../integrations/zellij/browse.nu
use assert.nu *

def plain [s: string]: nothing -> string { $s | ansi strip }

def agent [extra: record]: nothing -> record {
    {id: "0123456789abcdef", client: "claude", state: "working"} | merge $extra
}

export def main [] {
    # ── which agent comes first ──────────────────────────────────────────────
    # A fleet list has exactly one useful order: whoever needs you most.
    let mixed = [
        (agent {id: "w", state: "working", name: "worker"})
        (agent {id: "i", state: "idle", name: "resting"})
        (agent {id: "a", state: "needs-attention", name: "stuck"})
        (agent {id: "b", state: "awaiting", name: "waiting"})
    ]
    let a = [
        (check "most urgent first, and idle last — not hidden, just last"
               (browse rows $mixed | each {|r| $r.rec.id }) ["a" "b" "w" "i"])
        (check "every row carries its record, so a pick needs no second lookup"
               (browse rows $mixed | first | get rec.name) "stuck")
        (check "an empty store makes no rows at all" (browse rows []) [])
    ]

    # ── what a row says ──────────────────────────────────────────────────────
    let one = browse rows [(agent {name: "build-the-thing", cwd: "/a/b"
                                   zellij: {session: "home", tab_base: "root"}
                                   message: "All green."})]
    let row = plain ($one | first | get row)
    let b = [
        (check "the state is spelled out, not just coloured" ($row | str contains "working") true)
        (check "…and wears the same glyph the pane titles and the bar do"
               ($row | str starts-with "\u{f021}") true)
        (check "the agent's own name is the column you read"
               ($row | str contains "build-the-thing") true)
        (check "…then where it lives" ($row | str contains "home/root") true)
        (check "…then what it last said, so you can search for it"
               ($row | str contains "All green.") true)
    ]

    # ── the columns line up ──────────────────────────────────────────────────
    # Padding is what makes a list scannable, and it is counted in CHARACTERS:
    # plain `str length` counts bytes, so a "·" in a name would buy itself a
    # column it does not occupy.
    let pair = browse rows [
        (agent {id: "1", state: "needs-attention", name: "aa", zellij: {session: "s", tab_base: "t"}})
        (agent {id: "2", state: "working", name: "bbbbbbbb", zellij: {session: "s", tab_base: "t"}})
    ]
    let c = [
        (check "the state is padded, so every name starts in the same column"
               ((plain ($pair | get 1.row)) | str index-of "bbbbbbbb")
               ((plain ($pair | get 0.row)) | str index-of "aa"))
        (check "…and the name is too, so every `where` does as well"
               (($pair | each {|r| (plain $r.row) | str index-of "s/t" }) | uniq | length) 1)
    ]

    # ── what a row falls back to ─────────────────────────────────────────────
    let d = [
        (check "with no name, the directory it is working in"
               (plain (browse rows [(agent {cwd: "/x/monomodules"})] | first | get row)
                | str contains "monomodules") true)
        (check "with neither, enough of its id to tell it apart"
               (plain (browse rows [(agent {})] | first | get row) | str contains "01234567") true)
        (check "an idle agent gets a space where a glyph would be, so the column holds"
               (plain (browse rows [(agent {state: "idle", name: "n"})] | first | get row)
                | str starts-with "  n") false)
        (check "an agent outside zellij simply has nothing in the `where` column"
               (plain (browse rows [(agent {name: "n", message: "hi"})] | first | get row)
                | str contains "hi") true)
    ]

    # ── the message on the row is a GIST ─────────────────────────────────────
    # skim matches the whole row, so carrying a few sentences is what lets you
    # find an agent by something it said. Carrying the whole 4KB answer is a
    # fuzzy matcher chewing through text it can never show.
    let long = 1..200 | each {|i| $"word($i)" } | str join " "
    let gist = plain (browse rows [(agent {name: "n", message: $long})] | first | get row)
    let e = [
        (check "a long message is cut" (($gist | str length) < 400) true)
        (check "…and says that it was" ($gist | str ends-with "…") true)
        (check "a message with newlines still makes ONE row"
               (plain (browse rows [(agent {name: "n", message: "a\nb\nc"})] | first | get row)
                | lines | length) 1)
        (check "…with its lines run together, not swallowed"
               (plain (browse rows [(agent {name: "n", message: "a\nb"})] | first | get row)
                | str contains "a b") true)
    ]

    # ── the preview, which is most of the point ──────────────────────────────
    let now = date now | date to-timezone UTC | format date "%Y-%m-%dT%H:%M:%S%.6fZ"
    let old = (date now) - 4min | date to-timezone UTC | format date "%Y-%m-%dT%H:%M:%S%.6fZ"
    let pv = plain (browse preview (agent {name: "alpha", state: "awaiting", cwd: "/a/b"
                                           zellij: {session: "home", tab_base: "root"}
                                           state_since: $old, message: "Shall I?"}) 60)
    let f = [
        (check "it opens with who, and what they are doing" ($pv | str contains "alpha") true)
        (check "…and HOW LONG they have been doing it, which is the real question"
               ($pv | str contains "awaiting for 4m") true)
        (check "a fresh state reads as just now"
               (plain (browse preview (agent {name: "n", state_since: $now}) 60) | str contains "just now") true)
        (check "then where it lives, in full — the row only had room for a short form"
               ($pv | str contains "home/root  ·  /a/b") true)
        (check "then the message itself" ($pv | str contains "Shall I?") true)
        (check "an agent with nothing to say says so, rather than showing a blank pane"
               (plain (browse preview (agent {name: "n"}) 60) | str contains "no message") true)
        (check "a message keeps its OWN line structure — the row flattened it, this must not"
               (plain (browse preview (agent {name: "n", message: "one\n\ntwo"}) 60)
                | lines | where {|l| ($l | str trim) == "two" } | length) 1)
    ]

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f)
    summarise $all --title "browse"
}
