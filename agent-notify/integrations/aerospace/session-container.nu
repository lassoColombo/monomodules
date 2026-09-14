# aerospace as a SESSION-CONTAINER: which WINDOW an agent is in, and how to
# bring it to the front.
#
# THE OUTERMOST RUNG. A session is at a path (plan.md D77):
#
#     aerospace  ──▶  Ghostty  ──▶  zellij  ──▶  pane 7
#     window 39                     home/root
#
# and this answers for the first of those. Focusing a pane you cannot see
# changes nothing on your screen — that is the whole reason this file exists,
# and it is why a click on the bar used to land correctly and look like it had
# done nothing.
#
# ── IT CANNOT SEE ITSELF, WHICH SHAPES EVERYTHING BELOW ───────────────────────
# Every other coordinate in this module is discovered by the agent's own
# process: `$env.ZELLIJ_PANE_ID` is simply there. A WINDOW is not. Probed, and
# written up in §11 — there is no window id in Ghostty's environment, Ghostty
# has no CLI to focus one, aerospace reports the same `app-pid` for every window
# of an app, and the process ancestry dead-ends at the zellij SERVER, whose
# parent is 1. There is no walk from an agent to its window.
#
# The first design said: capture `aerospace list-windows --focused` once at
# session start, since the terminal is focused when you type `claude`. It was
# PROBED AND IT IS WRONG — caught live with the focus on Firefox on another
# workspace while the agent sat in Ghostty. And `discover-own-location` caches,
# so one wrong answer would be wrong for the life of the session.
#
# So this container DISCOVERS NOTHING AND STORES NOTHING. It finds the window at
# JUMP TIME, from what the record already says, every time. Nothing can go
# stale, there is no namespace to migrate, and the hot path never hears of it.
#
# ── WHAT IT SEARCHES BY, AND THE COUPLING THAT IMPLIES ────────────────────────
# zellij titles its terminal window `<session> | <active tab>`. The record
# already holds `zellij.session`. That is the only index from a record to a
# window that exists, so it is the one used.
#
# THIS IS A CROSS-CONTAINER READ AND IT IS DELIBERATE: the outermost container
# is identified by what an INNER one wrote. Step 12 asks whether that should be
# a contract member — a container publishing "the window I am in is titled like
# this" — and the answer is not yet, because one caller is not a contract. When
# tmux arrives it is one more line here, and at that point the generalisation
# has earned itself.
#
# It is NOT the thing D28 deleted. v1 recovered a NAME — a fact — by parsing it
# back out of a title. Here the fact is `zellij.session`, which comes from the
# record; the title is a LOOKUP KEY that finds the window carrying it. The two
# read alike from a distance and are not alike: nothing here would be believed
# if the title said something else.

use program.nu

export const INFO = {name: "aerospace", title: "aerospace windows"}

# What titles the window this session is in. Empty means we have no way to look,
# which is not a failure — it is an agent that is not in a terminal we can index.
#
# `| ` is zellij's own separator and is what makes the match specific enough to
# trust: `home ` would match any window whose title happens to start that way,
# `home | ` is a zellij client attached to the session called home.
def window-title-prefix [rec: record]: nothing -> string {
    let session = $rec.zellij?.session? | default ""
    if ($session | is-empty) { "" } else { $"($session) | " }
}

# PURE, and the reason the suite can assert this with no window manager on the
# machine: the world comes in as a list of records, and what comes back is the
# window id or "". Rule 3 of `integrations/mod.nu`, the same split as
# `render-items`/`push-items`.
#
# FIRST MATCH WINS. Two terminal windows attached to the SAME zellij session
# would both match — untested, §11 — and an arbitrary-but-stable answer beats a
# coin toss and beats refusing to move.
export def window-id-for [windows: list<record>, prefix: string]: nothing -> string {
    if ($prefix | is-empty) { return "" }
    $windows
    | where {|w| ($w.title? | default "") | str starts-with $prefix }
    | get -o 0.id
    | default ""
}

# Every window aerospace knows about. Empty when it cannot be asked, which reads
# as "nothing to do" rather than as a failure — see `program.nu`.
def all-windows [binary: string]: nothing -> list<record> {
    let r = try { ^$binary list-windows --all --format '%{window-id}|%{window-title}' | complete } catch { null }
    if ($r == null) or ($r.exit_code != 0) { return [] }
    $r.stdout | lines | each {|l|
        let p = $l | split row "|"
        {id: ($p | get 0 | str trim), title: ($p | skip 1 | str join "|" | str trim)}
    }
}

# What this container was told, validated — the `commands` half of its
# namespace. The ONLY reason `aerospace:` may appear in the config file at all:
# `config check` knows the tools from the registries, and a container-only
# integration is in no display registry, so without this it reads as a typo
# (plan.md D70 — an integration has capabilities, not a kind).
#
# Checked WHETHER OR NOT anything is in `displays:`, because nothing turns
# commands on — you run a jump and it runs.
#
# A `binary` that is not there is a LOUD error here and a quiet "" at jump time,
# and that is on purpose: a human asking "is my config right" wants to be told,
# and a jump wants to step past a window manager it cannot reach rather than
# take the pane focus down with it.
export def commands-settings [given: record] {
    for k in ($given | columns | where {|k| $k != "binary" }) {
        error make --unspanned {msg: $"aerospace: '($k)' is not a command setting \(try: binary\)"}
    }
    let given_binary = $given.binary? | default ""
    if ($given_binary | is-not-empty) and (not ($given_binary | path exists)) {
        error make --unspanned {msg: $"aerospace: no program at '($given_binary)'"}
    }
    {binary: (program from-setting $given_binary)}
}

# ── the contract ──────────────────────────────────────────────────────────────

# PURE, and it MUST be: `picker/rows.nu` asks this for every record every two
# seconds and on every keypress, so a subprocess here would be one per agent on
# a 2-second timer (plan.md step 12 phase 2).
#
# So it claims OPTIMISTICALLY — a session we could look for is a session we
# claim — and whether a window is actually there is settled in
# `focus-session-argv`, where a subprocess is already being run and a human is
# already waiting.
export def owns-session [rec: record]: nothing -> bool {
    (window-title-prefix $rec) | is-not-empty
}

# Nothing. A workspace number is not worth a column in a list of agents, and the
# session name beside it already says which machine-place this is. A container
# with nothing to say drops out of the path rather than padding it.
export def location-label [rec: record]: nothing -> string { "" }

# EMPTY MEANS "I HAVE NOTHING TO DO", AND THE WALK STEPS PAST IT. Three ways to
# get there, and none of them is a failure: no aerospace installed, no window
# titled for this session, or nothing to search by. The distinction matters —
# a failure STOPS the walk and would take the pane focus down with it.
export def focus-session-argv [rec: record]: nothing -> list<list<string>> {
    let binary = program resolve
    if ($binary | is-empty) { return [] }
    let id = window-id-for (all-windows $binary) (window-title-prefix $rec)
    if ($id | is-empty) { return [] }
    [[$binary "focus" "--window-id" $id]]
}

# Bring the window forward. Unlike zellij, aerospace tells the truth with its
# exit code — a window id it does not know exits 1 and says so (§11) — so there
# is no stderr vocabulary to keep here.
export def focus-session [rec: record]: nothing -> nothing {
    for cmd in (focus-session-argv $rec) {
        let r = ^($cmd | first) ...($cmd | skip 1) | complete
        if $r.exit_code != 0 {
            error make --unspanned {msg: ($r.stderr | str trim | default "aerospace: focus failed")}
        }
    }
}
