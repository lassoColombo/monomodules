# The zellij surface.
#
# Almost all of it is `project`, a pure function from records to a map, so almost
# none of this needs zellij: hand it records, read back the titles it wants. What
# would actually be run is readable too — `commands` returns the argv rather than
# running it — so the only thing not covered here is the subprocess itself, which
# cannot be tested without a live session to rename.

use ../../agent-notify2
use ../surfaces/zellij.nu
use ../core/dispatch.nu
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests-zellij")
const CFG = ($nu.temp-dir | path join "agent-notify2-tests-zellij" "config.yaml")
const FAKE = "agent-notify2-tests-no-such-session"

def rec [extra: record = {}]: nothing -> record {
    {id: "me-1", client: "claude", state: "working", name: "monomodules"
     zellij: {session: $FAKE, pane_id: "3"}} | merge $extra
}

export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    mkdir $TMP
    $env.XDG_DATA_HOME = $TMP
    $env.AGENT_NOTIFY_CONFIG = $CFG
    $env.AGENT_NOTIFY_ID = "me-1"
    $env.AGENT_NOTIFY_CLIENT = "claude"
    # A session name that cannot exist: this suite turns the surface ON, and a
    # rename aimed at a real session would retitle a pane the user is using.
    $env.ZELLIJ_SESSION_NAME = $FAKE
    $env.ZELLIJ_PANE_ID = "3"

    let s = zellij settings {}

    # ── settings: the config, and nothing else ───────────────────────────────
    let a = [
        (check "settings are settings — no environment, no identity"
               ($s | columns | sort) ["binary" "glyphs"])
        (check "every state has a glyph by default" ($s.glyphs | columns | sort)
               ["awaiting" "idle" "needs-attention" "working"])
        (check "idle is deliberately blank" $s.glyphs.idle "")
        (check "an override replaces just that one"
               (zellij settings {glyphs: {working: "W"}} | get glyphs.working) "W")
        (check "…and leaves the others alone"
               (zellij settings {glyphs: {working: "W"}} | get glyphs.awaiting) $s.glyphs.awaiting)
        (check "the program is resolved to an ABSOLUTE path, not left to PATH"
               ($s.binary | str starts-with "/") true)
        (check-err "…and a path that is not there is a loud error, not a silent no-op"
                   "no program at" {|| zellij settings {binary: "/nope/zellij"} })
        (check-err "a setting we do not have is a typo" "is not a setting"
                   {|| zellij settings {colour: "red"} })
        (check-err "a glyph for a state that does not exist is refused" "is not a state"
                   {|| zellij settings {glyphs: {sleeping: "z"}} })
        (check-err "a glyph must be a string" "must be a string"
                   {|| zellij settings {glyphs: {working: 3}} })
    ]

    # ── observe: the one thing that looks at the world ───────────────────────
    # `known` is what the store already holds. When it already knows the tab, no
    # lookup happens at all — which is what keeps the `list-panes` to once per
    # session. (The session here does not exist, so a lookup returns nothing extra
    # rather than inventing a tab.)
    let settled = {session: $FAKE, pane_id: "3", tab_id: "1", tab_base: "root"}
    let b = [
        (check "knowing the tab already, it looks at nothing and says where we are"
               (zellij observe $settled $s) {session: $FAKE, pane_id: "3"})
        (check "not knowing it, it goes and asks"
               (zellij observe {} $s) {session: $FAKE, pane_id: "3"})
        (check "a pane that has MOVED is looked up again"
               (zellij observe ($settled | update pane_id "99") $s) {session: $FAKE, pane_id: "3"})
        (check "…and outside zellij there is nothing to say"
               (with-env {ZELLIJ_PANE_ID: ""} { zellij observe {} $s }) {})
    ]

    # ── project: a map, keyed by pane ────────────────────────────────────────
    let m = zellij project [(rec)] $s
    let key = $"pane|($FAKE)|3"
    let c = [
        (check "one key per pane" ($m | columns) [$key])
        (check "the value carries everything apply needs"
               ($m | get $key | columns | sort) ["base" "kind" "pane_id" "session" "title"])
        (check "the title is glyph then name"
               ($m | get $key | get title) $"($s.glyphs.working) monomodules")
        (check "the base is the same title without the glyph"
               ($m | get $key | get base) "monomodules")
        (check "an agent whose pane we do not know projects to nothing"
               (zellij project [{id: "nowhere", state: "working"}] $s) {})
        (check "the name beats the cwd"
               (zellij project [(rec {cwd: "/a/b/elsewhere"})] $s | get $key | get title)
               $"($s.glyphs.working) monomodules")
        (check "…and the cwd's last part is the fallback"
               (zellij project [(rec {name: null, cwd: "/a/b/elsewhere"})] $s | get $key | get title)
               $"($s.glyphs.working) elsewhere")
        (check "idle shows the name and nothing else"
               (zellij project [(rec {state: "idle"})] $s | get $key | get title) "monomodules")
        (check "an agent with nothing to say asks for a blank, which means undo"
               (zellij project [{id: "me-1", state: "idle", zellij: {session: $FAKE, pane_id: "3"}}] $s
                | get $key | get title) "")
    ]

    # ── the gate's premise ───────────────────────────────────────────────────
    # If any of these fail, every Stop in the system starts calling zellij.
    let d = [
        (check "a message is invisible to a pane title"
               (zellij project [(rec {message: "a long answer"})] $s) (zellij project [(rec)] $s))
        (check "…so is a directory change"
               (zellij project [(rec {cwd: "/elsewhere"})] $s) (zellij project [(rec)] $s))
        (check "a state change IS visible"
               ((zellij project [(rec {state: "awaiting"})] $s) != (zellij project [(rec)] $s)) true)
    ]

    # ── what would actually be run ───────────────────────────────────────────
    let writes = zellij commands $m {} $s | first
    let undos = zellij commands {} $m $s | first
    let e = [
        (check "a write renames the pane" ("rename-pane" in $writes) true)
        (check "…in the right session, by id"
               ([($writes | get 2) ($writes | get 6)]) [$FAKE "3"])
        (check "…to the glyph and the name" ($writes | last) $"($s.glyphs.working) monomodules")
        (check "an undo puts the NAME back, not a blank" ($undos | last) "monomodules")
        (check "…because a blank would mean undo-rename-pane, which pops one rename"
               ("rename-pane" in $undos) true)
        (check "an agent with no name to keep really is handed back blank"
               (zellij commands {} {k: {kind: "pane", session: $FAKE, pane_id: "9", title: "x", base: ""}} $s
                | first | last) "9")
    ]

    # ── tabs: one glyph per agent, in front of the tab's own name ────────────
    def placed [id: string, state: string, name: string, pane: string]: nothing -> record {
        {id: $id, client: "claude", state: $state, name: $name
         zellij: {session: $FAKE, pane_id: $pane, tab_id: "1", tab_base: "root"}}
    }
    let t1 = zellij project [(placed "a" "working" "gg" "3")] $s
    let t2 = zellij project [(placed "a" "working" "gg" "3") (placed "b" "awaiting" "snip" "9")] $s
    let tabkey = $"tab|($FAKE)|1"
    let t = [
        (check "a tab gets a key of its own" ($t1 | columns | where {|k| $k | str starts-with "tab|" }) [$tabkey])
        (check "one agent, one glyph, then the tab's own name"
               ($t1 | get $tabkey | get title) $"($s.glyphs.working) root")
        (check "two agents, two glyphs — most urgent first"
               ($t2 | get $tabkey | get title)
               $"($s.glyphs.awaiting) ($s.glyphs.working) root")
        (check "the base is the tab's name alone, for when they all leave"
               ($t2 | get $tabkey | get base) "root")
        (check "agents with nothing to say leave the tab as it was"
               (zellij project [(placed "a" "idle" "gg" "3")] $s | get $tabkey | get title) "root")
        (check "an agent in no known tab contributes no tab key"
               (zellij project [(rec)] $s | columns | where {|k| $k | str starts-with "tab|" }) [])
        (check "a tab is renamed by id, not by position"
               ("--tab-id" in (zellij commands $t1 {} $s | last)) true)
        (check "…and when the last agent leaves, its name comes back alone"
               (zellij commands {} $t1 $s | last | last) "root")
    ]

    # ── end to end, with a stub for the one impure call ──────────────────────
    # The record first, while no config exists and therefore no surface runs — so
    # that the dispatch below really is this agent's FIRST paint.
    agent-notify2 store patch "me-1" {client: "claude", state: "working", name: "monomodules"} | ignore
    {surfaces: ["zellij"]} | to yaml | save --force $CFG
    let painted = $TMP | path join "painted"
    let spy = {zellij: {info: $zellij.INFO
                        settings: {|given| zellij settings $given }
                        observe: {|known, st| zellij observe $known $st }
                        project: {|recs, st| zellij project $recs $st }
                        apply: {|changed, removed, st|
                            $"((zellij commands $changed $removed $st) | to json --raw)\n"
                            | save --append $painted }}}

    let one = agent-notify2 store get "me-1"
    let two = {id: "other", client: "claude", state: "awaiting", name: "gg"
               zellij: {session: $FAKE, pane_id: "9"}}

    # `one` has no pane recorded — observe is what gives it one.
    let f1 = dispatch project [] [$one] --table $spy
    let f = [
        (check "observe writes where we are into the store"
               (agent-notify2 store get "me-1" | get zellij.pane_id) "3")
        (check "…so an agent paints its own pane on its very first event"
               ($f1 | first | get wrote) 1)
    ]

    let f2 = dispatch project [(agent-notify2 store get "me-1")] [(agent-notify2 store get "me-1")] --table $spy
    let f_gate = [
        (check "nothing moved, nothing sent" ($f2 | first | get action) "skipped")
    ]

    let stored = agent-notify2 store get "me-1"
    let f3 = dispatch project [$stored $two] [$stored] --table $spy
    let f_gone = [
        (check "an agent that vanished has its pane handed back"
               ($f3 | first | get undid) 1)
        (check "…and nothing else is touched" ($f3 | first | get wrote) 0)
    ]

    # ── a write from the command line reaches the surfaces ───────────────────
    # `store patch` is the PUBLIC API a foreign agent reports through (P5). When it
    # wrote straight at the store, such an agent updated it and never appeared.
    agent-notify2 store patch "me-1" {zellij: null} | ignore
    agent-notify2 store patch "cli-1" {client: "other", state: "working", name: "from-the-cli"} | ignore
    let g = [
        (check "a CLI write goes through the seam: the surface ran and observed"
               (agent-notify2 store get "me-1" | get -o zellij | is-not-empty) true)
        (check "…and what it observed is OUR pane, not that of the agent written about"
               (agent-notify2 store get "me-1" | get zellij.pane_id) "3")
        (check "a CLI drop still answers whether there was anything to drop"
               (agent-notify2 store drop "cli-1") true)
    ]

    let all = ($a ++ $b ++ $c ++ $d ++ $e ++ $t ++ $f ++ $f_gate ++ $f_gone ++ $g)
    summarise $all --title "zellij surface"
}
