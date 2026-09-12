# Step 4 — the zellij surface.
#
# Almost all of it is `project`, which is a pure function, so almost all of this
# needs no zellij: hand it records and settings, read back the titles it wants.
# That is the point of the pure/impure split, and it is what lets the gate run the
# same function twice per event.
#
# What is NOT covered here is the one call that reaches zellij itself. Renaming a
# pane cannot be tested without a live session to rename, and the only live
# session on this machine is the one you are reading this in. `apply` is tested
# for the part that is ours — the store write — with an empty list of panes, so
# not a single subprocess runs.

use ../../agent-notify2
use ../surfaces/zellij.nu
use ../core/dispatch.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-zellij")
const CFG = ($nu.temp-dir | path join "agent-notify2-tests-zellij" "config.yaml")

def rec [extra: record = {}]: nothing -> record {
    {id: "me-1", client: "claude", state: "working", name: "monomodules"} | merge $extra
}
def other [extra: record = {}]: nothing -> record {
    {id: "other-1", client: "claude", state: "awaiting", name: "gg"
     zellij: {session: "agent-notify2-tests-no-such-session", pane_id: "9"}} | merge $extra
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    mkdir $TMP
    $env.XDG_DATA_HOME = $TMP
    $env.AGENT_NOTIFY_CONFIG = $CFG
    $env.AGENT_NOTIFY_ID = "me-1"
    $env.AGENT_NOTIFY_CLIENT = "claude"
    # A session name that cannot exist: this suite turns the zellij surface ON, and
    # a rename aimed at a real session would retitle a pane the user is using.
    $env.ZELLIJ_SESSION_NAME = "agent-notify2-tests-no-such-session"
    $env.ZELLIJ_PANE_ID = "3"

    let s = zellij settings {} "me-1"

    # ── settings: strict, and aware of where it is running ───────────────────
    let a = [
        (check "every state has a glyph by default" ($s.glyphs | columns | sort)
               ["awaiting" "idle" "needs-attention" "working"])
        (check "idle is deliberately blank" $s.glyphs.idle "")
        (check "an override replaces just that one"
               (zellij settings {glyphs: {working: "W"}} "me-1" | get glyphs.working) "W")
        (check "…and leaves the others alone"
               (zellij settings {glyphs: {working: "W"}} "me-1" | get glyphs.awaiting) $s.glyphs.awaiting)
        (check "it is told which agent the event is about" $s.me.id "me-1")
        (check "…and which pane" $s.me.pane_id "3")
        (check "the program is resolved to an ABSOLUTE path, not left to PATH"
               ($s.binary | str starts-with "/") true)
        (check-err "…and a path that is not there is a loud error, not a silent no-op"
                   "no program at" {|| zellij settings {binary: "/nope/zellij"} "me-1" })
        (check-err "a setting we do not have is a typo, not a silent no-op"
                   "is not a setting" {|| zellij settings {colour: "red"} "me-1" })
        (check-err "a glyph for a state that does not exist is refused"
                   "is not a state" {|| zellij settings {glyphs: {sleeping: "z"}} "me-1" })
        (check-err "a glyph must be a string"
                   "must be a string" {|| zellij settings {glyphs: {working: 3}} "me-1" })
        (check-err "glyphs must be a map"
                   "must be a map" {|| zellij settings {glyphs: "none"} "me-1" })
    ]

    # ── project: the whole of the thinking ───────────────────────────────────
    let mine = zellij project [(rec)] $s | first
    let b = [
        (check "the pane we are in comes from the environment, with nothing stored"
               {session: $mine.session, pane_id: $mine.pane_id}
               {session: "agent-notify2-tests-no-such-session", pane_id: "3"})
        (check "the title is glyph then name" $mine.title $"($s.glyphs.working) monomodules")
        (check "another agent's pane comes from its own namespace"
               (zellij project [(other)] $s | first | get pane_id) "9")
        (check "an agent in no pane at all projects to nothing"
               (zellij project [{id: "nowhere", state: "working"}] $s) [])
        (check "the name beats the cwd"
               (zellij project [(rec {cwd: "/a/b/elsewhere"})] $s | first | get title)
               $"($s.glyphs.working) monomodules")
        (check "…and the cwd's last part is the fallback"
               (zellij project [(rec {name: null, cwd: "/a/b/elsewhere"})] $s | first | get title)
               $"($s.glyphs.working) elsewhere")
        (check "idle shows the name and nothing else"
               (zellij project [(rec {state: "idle"})] $s | first | get title) "monomodules")
        (check "needing attention shows its own shape"
               (zellij project [(rec {state: "needs-attention"})] $s | first | get title)
               $"($s.glyphs.needs-attention) monomodules")
        (check "an agent with nothing to say asks for a blank, which drops our name"
               (zellij project [{id: "me-1", state: "idle"}] $s | first | get title) "")
        (check "panes come out in a stable order"
               (zellij project [(other) (rec)] $s | get pane_id) ["3" "9"])
    ]

    # ── the gate's premise, stated as a test ─────────────────────────────────
    # If this ever fails, every `Stop` in the system starts calling zellij.
    let with_msg = zellij project [(rec {message: "a long answer", updated_at: "later"})] $s
    let c = [
        (check "a message is invisible to a pane title, so a Stop repaints nothing"
               $with_msg (zellij project [(rec)] $s))
        (check "a state change IS visible"
               ((zellij project [(rec {state: "awaiting"})] $s) != (zellij project [(rec)] $s)) true)
    ]

    # ── the gate, end to end, with a stub for the one impure call ────────────
    {surfaces: ["zellij"]} | to yaml | save --force $CFG
    mut painted = []
    let spy = {zellij: {info: $zellij.INFO
                        settings: {|given, me| zellij settings $given $me }
                        project: {|recs, st| zellij project $recs $st }
                        apply: {|desired, prev, st| $"($desired | to json --raw)\n" | save --append ($TMP | path join "painted") }}}

    let r1 = agent-notify2 store patch "me-1" {client: "claude", state: "working", name: "monomodules"}
    let d1 = dispatch project $r1.before $r1.after --table $spy
    let r2 = agent-notify2 store patch "me-1" {message: "an answer"}
    let d2 = dispatch project $r2.before $r2.after --table $spy
    let r3 = agent-notify2 store patch "me-1" {state: "awaiting"}
    let d3 = dispatch project $r3.before $r3.after --table $spy
    let painted_lines = open --raw ($TMP | path join "painted") | lines | length
    let d = [
        (check "a new agent paints" ($d1 | first | get action) "applied")
        (check "a message-only change does not" ($d2 | first | get action) "skipped")
        (check "a state change does" ($d3 | first | get action) "applied")
        (check "so zellij was reached exactly twice" $painted_lines 2)
    ]

    # ── apply: the half that is ours ─────────────────────────────────────────
    # An empty list of panes, so nothing is renamed and no subprocess runs. A
    # surface never writes the store — it REPORTS, and dispatch records it, which
    # is also what keeps this file out of the store's import cone (§10).
    let learned = zellij apply [] null $s

    # …and dispatch is what writes it down. A recorder: the real surface, with
    # `apply` handed an empty list so it reports without painting anything.
    let recorder = {zellij: {info: $zellij.INFO
                             settings: {|given, me| zellij settings $given $me }
                             project: {|recs, st| zellij project $recs $st }
                             apply: {|desired, prev, st| zellij apply [] null $st }}}
    let r4 = agent-notify2 store patch "me-1" {state: "needs-attention"}
    dispatch project $r4.before $r4.after --table $recorder | ignore
    let stored = agent-notify2 store get "me-1"
    let e = [
        (check "apply reports where this agent lives" $learned
               {zellij: {session: "agent-notify2-tests-no-such-session", pane_id: "3"}})
        (check "…and dispatch is what wrote it down" $stored.zellij.pane_id "3")
        (check "…in which session" $stored.zellij.session "agent-notify2-tests-no-such-session")
        (check "which is what lets a repaint from outside zellij find it"
               (zellij project [$stored] {glyphs: $s.glyphs, me: {id: "", session: "", pane_id: ""}}
                | first | get pane_id) "3")
        (check "an agent in no pane has nothing to report"
               (zellij apply [] null {glyphs: $s.glyphs, me: {id: "x", session: "", pane_id: ""}}) null)
    ]

    # ── a forced repaint, from inside the agent's own pane ───────────────────
    # Without being told who it is, `--force` has no event to learn from and the
    # agent's own pane is the one pane it cannot paint.
    let blind = dispatch project --force --table $recorder
    let told = dispatch project --force --me "me-1" --table $recorder
    let f = [
        (check "a forced repaint still runs" ($told | first | get action) "applied")
        (check "…and told who it is, it can paint its own pane"
               (zellij project [(agent-notify2 store get "me-1")] (zellij settings {} "me-1")
                | length) 1)
        (check "a blind force does not fail, it just has less to say"
               ($blind | first | get action) "applied")
    ]

    # ── a write from the command line reaches the surfaces ───────────────────
    # `store patch` is the PUBLIC API a foreign agent reports through (P5). When it
    # wrote straight to the store — as it did until this test existed — such an
    # agent updated the store and never appeared on any surface at all. The proof
    # is indirect and exact: the zellij namespace only lands on a record if
    # dispatch ran and recorded what the surface reported back.
    # Forget where we are. This write cannot change what zellij shows — the pane
    # comes from the environment for our own record either way — so the gate skips
    # it and nothing puts the fact back.
    agent-notify2 store patch "me-1" {zellij: null} | ignore
    let forgotten = agent-notify2 store get "me-1" | get -o zellij

    # A write about a DIFFERENT agent, with a pane of its own, so the picture
    # genuinely changes. If the CLI reached the seam, the surface ran; if the
    # surface ran, it reported where WE are and dispatch wrote it down.
    agent-notify2 store patch "cli-1" {
        client: "other", state: "working", name: "from-the-cli"
        zellij: {session: "agent-notify2-tests-no-such-session", pane_id: "42"}
    } | ignore
    let g = [
        (check "a write that cannot change the picture is skipped, so the fact stays gone"
               $forgotten null)
        (check "a CLI write goes through the seam: the surface ran and reported back"
               (agent-notify2 store get "me-1" | get -o zellij | is-not-empty) true)
        (check "…and what it reported is OUR pane, not the pane of the agent written about"
               (agent-notify2 store get "me-1" | get zellij.pane_id) "3")
        (check "…while the foreign agent keeps its own" 
               (agent-notify2 store get "cli-1" | get zellij.pane_id) "42")
        (check "a CLI drop still answers whether there was anything to drop"
               (agent-notify2 store drop "cli-1") true)
    ]

    # ── which panes actually get written ─────────────────────────────────────
    # The decision, as data. This is where "an agent that ended leaves its glyph
    # behind forever" is prevented, and where a pane that did not move is spared
    # an 11ms subprocess.
    let one = {session: "s", pane_id: "1", title: "A one", base: "one"}
    let two = {session: "s", pane_id: "2", title: "B two", base: "two"}
    let h = [
        (check "with nothing before, everything is written"
               (zellij renames [$one $two] null | length) 2)
        (check "a pane whose title did not move is left alone"
               (zellij renames [$one $two] [$one] | get pane_id) ["2"])
        (check "nothing moved means nothing is written"
               (zellij renames [$one $two] [$one $two]) [])
        (check "a pane we no longer own is handed back"
               (zellij renames [$one] [$one $two] | get pane_id) ["2"])
        (check "…keeping its NAME and losing only the glyph"
               (zellij renames [$one] [$one $two] | get title) ["two"])
        (check "an agent that ended releases its pane and nothing else"
               (zellij renames [] [$one $two] | get title) ["one" "two"])
        (check "a pane with no name to keep is handed back blank, which means undo"
               (zellij renames [] [($two | update base "")] | get title) [""])
        (check "a title change and a release in one go"
               (zellij renames [($one | update title "A changed")] [$one $two]
                | select pane_id title)
               [{pane_id: "1", title: "A changed"} {pane_id: "2", title: "two"}])
    ]

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $f ++ $g ++ $h)
    summarise $all --title "zellij surface"
}
