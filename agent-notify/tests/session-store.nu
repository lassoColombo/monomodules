# Step 1 verification — exercises every rule the session-store claims to
# enforce.
use ../../agent-notify
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests")




export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # display on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    mut r = []

    # ── create ────────────────────────────────────────────────────────────────
    let c = agent-notify session-store patch "abc-123" {agent: "claude", state: "working", cwd: "/tmp"}
    $r = $r ++ [(check "create reports changed" $c.changed true)]
    $r = $r ++ [(check "create has no before" $c.before null)]
    $r = $r ++ [(check "create stores state" $c.after.state "working")]
    $r = $r ++ [(check "create stamps version" $c.after.schema_version 1)]
    $r = $r ++ [(check "create stamps state_since" ($c.after.state_since | is-not-empty) true)]
    $r = $r ++ [(check "readable back" (agent-notify session-store get "abc-123" | get state) "working")]

    # ── the `changed` gate ────────────────────────────────────────────────────
    let same = agent-notify session-store patch "abc-123" {state: "working"}
    $r = $r ++ [(check "re-asserting the same state is not a change" $same.changed false)]
    $r = $r ++ [(check "unchanged write returns the existing record" $same.after.state "working")]
    let since1 = agent-notify session-store get "abc-123" | get state_since
    let moved = agent-notify session-store patch "abc-123" {state: "awaiting"}
    $r = $r ++ [(check "a real state change is a change" $moved.changed true)]
    $r = $r ++ [(check "state_since moves with the state" ($moved.after.state_since != $since1) true)]
    let other = agent-notify session-store patch "abc-123" {message: "hello"}
    $r = $r ++ [(check "an unrelated field is still a change" $other.changed true)]
    $r = $r ++ [(check "state_since does NOT move for unrelated writes"
                       ($other.after.state_since == $moved.after.state_since) true)]

    # ── deep merge and null deletes ───────────────────────────────────────────
    agent-notify session-store patch "abc-123" {zellij: {session: "home", pane_id: 3, tab_id: 0}}
    agent-notify session-store patch "abc-123" {zellij: {tab_id: 4}}
    let z = agent-notify session-store get "abc-123" | get zellij
    $r = $r ++ [(check "deep merge updates one namespaced field" $z.tab_id 4)]
    $r = $r ++ [(check "deep merge preserves its siblings" $z.session "home")]
    agent-notify session-store patch "abc-123" {message: null}
    $r = $r ++ [(check "null deletes a field"
                       ("message" in (agent-notify session-store get "abc-123" | columns)) false)]
    agent-notify session-store patch "abc-123" {zellij: {tab_id: null}}
    let z2 = agent-notify session-store get "abc-123" | get zellij
    $r = $r ++ [(check "null deletes inside a namespace" ("tab_id" in ($z2 | columns)) false)]
    $r = $r ++ [(check "…without taking its siblings" $z2.pane_id 3)]

    # ── strictness ────────────────────────────────────────────────────────────
    $r = $r ++ [(check-err "unknown state is rejected" "unknown state" {||
        agent-notify session-store patch "abc-123" {state: "busy"} })]
    $r = $r ++ [(check-err "a record with no agent is rejected" "missing required field 'agent'" {||
        agent-notify session-store patch "no-agent" {state: "idle"} })]
    $r = $r ++ [(check-err "a non-record namespace is rejected" "must be a namespace" {||
        agent-notify session-store patch "abc-123" {zellij: 5} })]
    $r = $r ++ [(check-err "a mistyped core field is rejected" "must be a string" {||
        agent-notify session-store patch "abc-123" {name: 42} })]
    $r = $r ++ [(check "a rejected write leaves nothing behind"
                       (agent-notify session-store get "no-agent") null)]

    # ── opaque ids ────────────────────────────────────────────────────────────
    agent-notify session-store patch "../../etc/passwd" {agent: "evil", state: "idle"}
    let escaped = ls ($"($TMP)/agent-notify/sessions/*.json" | into glob) | get name | path basename
    $r = $r ++ [(check "a traversing id cannot escape the session-store"
                       ($escaped | any {|f| $f | str contains ".." }) false)]
    $r = $r ++ [(check "no id can produce a hidden (unlistable) file"
                       ($escaped | any {|f| $f | str starts-with "." }) false)]
    $r = $r ++ [(check "an awkward id is still readable by id"
                       (agent-notify session-store get "../../etc/passwd" | get agent) "evil")]
    agent-notify session-store patch "a/b" {agent: "x", state: "idle"}
    agent-notify session-store patch "a_b" {agent: "y", state: "idle"}
    $r = $r ++ [(check "ids that v1 would collide stay distinct"
                       [(agent-notify session-store get "a/b" | get agent) (agent-notify session-store get "a_b" | get agent)]
                       ["x" "y"])]

    # ── list, set, drop ───────────────────────────────────────────────────────
    $r = $r ++ [(check "list sees every record" (agent-notify session-store list | length) 4)]
    let s = agent-notify session-store set "abc-123" {agent: "claude", state: "idle"}
    $r = $r ++ [(check "set replaces rather than merges"
                       ("zellij" in ($s.after | columns)) false)]
    $r = $r ++ [(check "drop files it away" (agent-notify session-store end "abc-123") true)]
    $r = $r ++ [(check "drop is idempotent" (agent-notify session-store end "abc-123") false)]
    $r = $r ++ [(check "a dropped record is off the LIVE session-store" (agent-notify session-store get "abc-123") null)]

    # ── a session ends, and is resumed ────────────────────────────────────────
    # A session is not destroyed when it stops running — Claude Code does not
    # destroy one, and neither does zellij or tmux. The NAME is why it matters
    # here: everything else in a record is re-supplied by the next event, and a
    # name is authored once and then never said again by anybody.
    agent-notify session-store patch "resume-me" {
        agent: "claude", state: "working", name: "the-name", cwd: "/tmp/proj"
        message: "last thing", process: {pid: 99999, started: "2026-01-01"}
        zellij: {session: "home", pane_id: "7"}
    } | ignore
    agent-notify session-store end "resume-me" | ignore
    $r = $r ++ [
        (check "ending a session takes it off the live session-store"
               (agent-notify session-store get "resume-me") null)
        (check "…and files it away rather than destroying it"
               (agent-notify session-store list --ended | where id == "resume-me" | get 0.name) "the-name")
    ]

    # The resume. The SAME id, because that is what `--resume` hands back —
    # `--fork-session` exists to opt out of it. Shaped like a SessionStart: a
    # write that CREATES and carries defaults, which is the only write that can
    # be a resume.
    agent-notify report --id "resume-me" --agent "claude" --cwd "/tmp/proj" | ignore
    let back = agent-notify session-store get "resume-me"
    $r = $r ++ [
        (check "RESUMING A SESSION BRINGS ITS NAME BACK" $back.name "the-name")
        (check "…along with what it last said" $back.message "last thing")
        (check "…and it is idle until you type, not still doing what it was doing"
               $back.state "idle")
        (check "THE RUN IT WAS IN DOES NOT COME BACK — a stale pid would let the store-garbage-collector
           prove a live session dead within 30s, and a stale pane would rename
           a pane that has moved on"
               ($back | columns | where {|c| $c in ["process" "zellij"] }) [])
        (check "…and the filed copy is consumed, not left in both places"
               (agent-notify session-store list --ended | where id == "resume-me") [])
        (check "a session nobody filed away is created, not reopened"
               (agent-notify report --id "brand-new" --agent "claude" | get after.state) "idle")
    ]

    # ── naming, and not re-naming ─────────────────────────────────────────────
    # `--if-unnamed` is what lets CLAUDE.md say "run this at every session start"
    # without qualification: on a resumed session the name is already back, and
    # re-deriving one would make the stable thing unstable.
    agent-notify report --id "namer" --agent "claude" | ignore
    let first = agent-notify name "chosen" --id "namer" --if-unnamed
    let second = agent-notify name "something-else" --id "namer" --if-unnamed
    $r = $r ++ [
        (check "--if-unnamed names a session that has none" $first.after.name "chosen")
        (check "…and leaves one that already has a name alone"
               (agent-notify session-store get "namer" | get name) "chosen")
        (check "…writing nothing at all, so no display hears about it" $second.changed false)
        (check "without the flag it is still a plain rename"
               (agent-notify name "renamed" --id "namer" | get after.name) "renamed")
    ]

    # ── reaping ───────────────────────────────────────────────────────────────
    # On ending, the only moment the directory can grow, and by MTIME — so the
    # scan opens nothing. `touch` fakes the age, which is the whole point of
    # using mtime: no field to write, and nothing to parse to read it back.
    agent-notify session-store patch "old-one" {agent: "claude", state: "idle", name: "ancient"} | ignore
    agent-notify session-store end "old-one" | ignore
    # Older than the 7-day keep window, faked with `touch` — which is the point
    # of using mtime: no field to write, and nothing to parse to read it back.
    ^touch -mt 202001010000 ($TMP | path join "agent-notify" "ended" "old-one.json")
    agent-notify session-store patch "fresh-one" {agent: "claude", state: "idle", name: "recent"} | ignore
    agent-notify session-store end "fresh-one" | ignore
    $r = $r ++ [
        (check "an ended session past the keep window expires when the next ends"
               (agent-notify session-store list --ended | where id == "old-one") [])
        (check "…and a recent one is left alone"
               (agent-notify session-store list --ended | where id == "fresh-one" | get 0.name) "recent")
    ]

    # ── no litter ─────────────────────────────────────────────────────────────
    let tmps = ls ($"($TMP)/agent-notify/sessions/*" | into glob) | get name | where {|f| $f | str ends-with ".tmp" }
    $r = $r ++ [(check "atomic writes leave no temp files" ($tmps | length) 0)]

    # ── the empty session-store ───────────────────────────────────────────────
    # A glob that matches nothing is an ERROR in nushell, and a store whose last
    # agent has just ended is exactly that: the directory outlives its contents.
    agent-notify session-store list | get id | each {|id| agent-notify session-store end $id } | ignore
    $r = $r ++ [(check "an emptied session-store lists as nothing, not an error"
                       (agent-notify session-store list) [])]
    rm --recursive --force ($TMP | path join "agent-notify" "ended")
    $r = $r ++ [(check "…and so does an archive that has never been written to"
                       (agent-notify session-store list --ended) [])]

    summarise $r --title "session-store"
}
