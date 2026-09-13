# Step 1 verification — exercises every rule the store claims to enforce.
use ../../agent-notify
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify-tests")




export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # surface on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    mut r = []

    # ── create ───────────────────────────────────────────────────────────────
    let c = agent-notify store patch "abc-123" {client: "claude", state: "working", cwd: "/tmp"}
    $r = $r ++ [(check "create reports changed" $c.changed true)]
    $r = $r ++ [(check "create has no before" $c.before null)]
    $r = $r ++ [(check "create stores state" $c.after.state "working")]
    $r = $r ++ [(check "create stamps version" $c.after.v 1)]
    $r = $r ++ [(check "create stamps state_since" ($c.after.state_since | is-not-empty) true)]
    $r = $r ++ [(check "readable back" (agent-notify store get "abc-123" | get state) "working")]

    # ── the `changed` gate ───────────────────────────────────────────────────
    let same = agent-notify store patch "abc-123" {state: "working"}
    $r = $r ++ [(check "re-asserting the same state is not a change" $same.changed false)]
    $r = $r ++ [(check "unchanged write returns the existing record" $same.after.state "working")]
    let since1 = agent-notify store get "abc-123" | get state_since
    let moved = agent-notify store patch "abc-123" {state: "awaiting"}
    $r = $r ++ [(check "a real state change is a change" $moved.changed true)]
    $r = $r ++ [(check "state_since moves with the state" ($moved.after.state_since != $since1) true)]
    let other = agent-notify store patch "abc-123" {message: "hello"}
    $r = $r ++ [(check "an unrelated field is still a change" $other.changed true)]
    $r = $r ++ [(check "state_since does NOT move for unrelated writes"
                       ($other.after.state_since == $moved.after.state_since) true)]

    # ── deep merge and null deletes ──────────────────────────────────────────
    agent-notify store patch "abc-123" {zellij: {session: "home", pane_id: 3, tab_id: 0}}
    agent-notify store patch "abc-123" {zellij: {tab_id: 4}}
    let z = agent-notify store get "abc-123" | get zellij
    $r = $r ++ [(check "deep merge updates one namespaced field" $z.tab_id 4)]
    $r = $r ++ [(check "deep merge preserves its siblings" $z.session "home")]
    agent-notify store patch "abc-123" {message: null}
    $r = $r ++ [(check "null deletes a field"
                       ("message" in (agent-notify store get "abc-123" | columns)) false)]
    agent-notify store patch "abc-123" {zellij: {tab_id: null}}
    let z2 = agent-notify store get "abc-123" | get zellij
    $r = $r ++ [(check "null deletes inside a namespace" ("tab_id" in ($z2 | columns)) false)]
    $r = $r ++ [(check "…without taking its siblings" $z2.pane_id 3)]

    # ── strictness ───────────────────────────────────────────────────────────
    $r = $r ++ [(check-err "unknown state is rejected" "unknown state" {||
        agent-notify store patch "abc-123" {state: "busy"} })]
    $r = $r ++ [(check-err "a record with no client is rejected" "missing required field 'client'" {||
        agent-notify store patch "no-client" {state: "idle"} })]
    $r = $r ++ [(check-err "a non-record namespace is rejected" "must be a namespace" {||
        agent-notify store patch "abc-123" {zellij: 5} })]
    $r = $r ++ [(check-err "a mistyped core field is rejected" "must be a string" {||
        agent-notify store patch "abc-123" {name: 42} })]
    $r = $r ++ [(check "a rejected write leaves nothing behind"
                       (agent-notify store get "no-client") null)]

    # ── opaque ids ───────────────────────────────────────────────────────────
    agent-notify store patch "../../etc/passwd" {client: "evil", state: "idle"}
    let escaped = ls ($"($TMP)/agent-notify/agents/*.json" | into glob) | get name | path basename
    $r = $r ++ [(check "a traversing id cannot escape the store"
                       ($escaped | any {|f| $f | str contains ".." }) false)]
    $r = $r ++ [(check "no id can produce a hidden (unlistable) file"
                       ($escaped | any {|f| $f | str starts-with "." }) false)]
    $r = $r ++ [(check "an awkward id is still readable by id"
                       (agent-notify store get "../../etc/passwd" | get client) "evil")]
    agent-notify store patch "a/b" {client: "x", state: "idle"}
    agent-notify store patch "a_b" {client: "y", state: "idle"}
    $r = $r ++ [(check "ids that v1 would collide stay distinct"
                       [(agent-notify store get "a/b" | get client) (agent-notify store get "a_b" | get client)]
                       ["x" "y"])]

    # ── list, set, drop ──────────────────────────────────────────────────────
    $r = $r ++ [(check "list sees every record" (agent-notify store list | length) 4)]
    let s = agent-notify store set "abc-123" {client: "claude", state: "idle"}
    $r = $r ++ [(check "set replaces rather than merges"
                       ("zellij" in ($s.after | columns)) false)]
    $r = $r ++ [(check "drop files it away" (agent-notify store drop "abc-123") true)]
    $r = $r ++ [(check "drop is idempotent" (agent-notify store drop "abc-123") false)]
    $r = $r ++ [(check "a dropped record is off the LIVE store" (agent-notify store get "abc-123") null)]

    # ── a session ends, and is resumed ───────────────────────────────────────
    # A session is not destroyed when it stops running — Claude Code does not
    # destroy one, and neither does zellij or tmux. The NAME is why it matters
    # here: everything else in a record is re-supplied by the next event, and a
    # name is authored once and then never said again by anybody.
    agent-notify store patch "resume-me" {
        client: "claude", state: "working", name: "the-name", cwd: "/tmp/proj"
        message: "last thing", proc: {pid: 99999, started: "2026-01-01"}
        zellij: {session: "home", pane_id: "7"}
    } | ignore
    agent-notify store drop "resume-me" | ignore
    $r = $r ++ [
        (check "ending a session takes it off the live store"
               (agent-notify store get "resume-me") null)
        (check "…and files it away rather than destroying it"
               (agent-notify store list --ended | where id == "resume-me" | get 0.name) "the-name")
    ]

    # The resume. The SAME id, because that is what `--resume` hands back —
    # `--fork-session` exists to opt out of it. Shaped like a SessionStart: a
    # write that CREATES and carries defaults, which is the only write that can
    # be a resume.
    agent-notify report --id "resume-me" --client "claude" --cwd "/tmp/proj" | ignore
    let back = agent-notify store get "resume-me"
    $r = $r ++ [
        (check "RESUMING A SESSION BRINGS ITS NAME BACK" $back.name "the-name")
        (check "…along with what it last said" $back.message "last thing")
        (check "…and it is idle until you type, not still doing what it was doing"
               $back.state "idle")
        (check "THE RUN IT WAS IN DOES NOT COME BACK — a stale pid would let the janitor
           prove a live session dead within 30s, and a stale pane would rename
           a pane that has moved on"
               ($back | columns | where {|c| $c in ["proc" "zellij"] }) [])
        (check "…and the filed copy is consumed, not left in both places"
               (agent-notify store list --ended | where id == "resume-me") [])
        (check "a session nobody filed away is created, not restored"
               (agent-notify report --id "brand-new" --client "claude" | get after.state) "idle")
    ]

    # ── reaping ──────────────────────────────────────────────────────────────
    # On archive, the only moment the directory can grow, and by MTIME — so the
    # scan opens nothing. `touch` fakes the age, which is the whole point of
    # using mtime: no field to write, and nothing to parse to read it back.
    agent-notify store patch "old-one" {client: "claude", state: "idle", name: "ancient"} | ignore
    agent-notify store drop "old-one" | ignore
    ^touch -mt 202001010000 ($TMP | path join "agent-notify" "ended" "old-one.json")
    agent-notify store patch "fresh-one" {client: "claude", state: "idle", name: "recent"} | ignore
    agent-notify store drop "fresh-one" | ignore
    $r = $r ++ [
        (check "an ended session past the keep window is reaped by the next archive"
               (agent-notify store list --ended | where id == "old-one") [])
        (check "…and a recent one is left alone"
               (agent-notify store list --ended | where id == "fresh-one" | get 0.name) "recent")
    ]

    # ── no litter ────────────────────────────────────────────────────────────
    let tmps = ls ($"($TMP)/agent-notify/agents/*" | into glob) | get name | where {|f| $f | str ends-with ".tmp" }
    $r = $r ++ [(check "atomic writes leave no temp files" ($tmps | length) 0)]

    # ── the empty store ──────────────────────────────────────────────────────
    # A glob that matches nothing is an ERROR in nushell, and a store whose last
    # agent has just ended is exactly that: the directory outlives its contents.
    agent-notify store list | get id | each {|id| agent-notify store drop $id } | ignore
    $r = $r ++ [(check "an emptied store lists as nothing, not an error"
                       (agent-notify store list) [])]
    rm --recursive --force ($TMP | path join "agent-notify" "ended")
    $r = $r ++ [(check "…and so does an archive that has never been written to"
                       (agent-notify store list --ended) [])]

    summarise $r --title "store"
}
