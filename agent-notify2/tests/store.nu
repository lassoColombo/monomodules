# Step 1 verification — exercises every rule the store claims to enforce.
use ../../agent-notify2
use assert.nu *

const TMP = ($nu.temp-dir | path join "agent-notify2-tests")




export def main [] {
    if ($TMP | path exists) { rm --recursive --force $TMP }
    $env.XDG_DATA_HOME = $TMP
    # Point at a config that does not exist: a real one could switch a real
    # surface on, and a test must never paint a pane the user is looking at.
    $env.AGENT_NOTIFY_CONFIG = ($TMP | path join "no-config.yaml")

    mut r = []

    # ── create ───────────────────────────────────────────────────────────────
    let c = agent-notify2 store patch "abc-123" {client: "claude", state: "working", cwd: "/tmp"}
    $r = $r ++ [(check "create reports changed" $c.changed true)]
    $r = $r ++ [(check "create has no before" $c.before null)]
    $r = $r ++ [(check "create stores state" $c.after.state "working")]
    $r = $r ++ [(check "create stamps version" $c.after.v 1)]
    $r = $r ++ [(check "create stamps state_since" ($c.after.state_since | is-not-empty) true)]
    $r = $r ++ [(check "readable back" (agent-notify2 store get "abc-123" | get state) "working")]

    # ── the `changed` gate ───────────────────────────────────────────────────
    let same = agent-notify2 store patch "abc-123" {state: "working"}
    $r = $r ++ [(check "re-asserting the same state is not a change" $same.changed false)]
    $r = $r ++ [(check "unchanged write returns the existing record" $same.after.state "working")]
    let since1 = agent-notify2 store get "abc-123" | get state_since
    let moved = agent-notify2 store patch "abc-123" {state: "awaiting"}
    $r = $r ++ [(check "a real state change is a change" $moved.changed true)]
    $r = $r ++ [(check "state_since moves with the state" ($moved.after.state_since != $since1) true)]
    let other = agent-notify2 store patch "abc-123" {message: "hello"}
    $r = $r ++ [(check "an unrelated field is still a change" $other.changed true)]
    $r = $r ++ [(check "state_since does NOT move for unrelated writes"
                       ($other.after.state_since == $moved.after.state_since) true)]

    # ── deep merge and null deletes ──────────────────────────────────────────
    agent-notify2 store patch "abc-123" {zellij: {session: "home", pane_id: 3, tab_id: 0}}
    agent-notify2 store patch "abc-123" {zellij: {tab_id: 4}}
    let z = agent-notify2 store get "abc-123" | get zellij
    $r = $r ++ [(check "deep merge updates one namespaced field" $z.tab_id 4)]
    $r = $r ++ [(check "deep merge preserves its siblings" $z.session "home")]
    agent-notify2 store patch "abc-123" {message: null}
    $r = $r ++ [(check "null deletes a field"
                       ("message" in (agent-notify2 store get "abc-123" | columns)) false)]
    agent-notify2 store patch "abc-123" {zellij: {tab_id: null}}
    let z2 = agent-notify2 store get "abc-123" | get zellij
    $r = $r ++ [(check "null deletes inside a namespace" ("tab_id" in ($z2 | columns)) false)]
    $r = $r ++ [(check "…without taking its siblings" $z2.pane_id 3)]

    # ── strictness ───────────────────────────────────────────────────────────
    $r = $r ++ [(check-err "unknown state is rejected" "unknown state" {||
        agent-notify2 store patch "abc-123" {state: "busy"} })]
    $r = $r ++ [(check-err "a record with no client is rejected" "missing required field 'client'" {||
        agent-notify2 store patch "no-client" {state: "idle"} })]
    $r = $r ++ [(check-err "a non-record namespace is rejected" "must be a namespace" {||
        agent-notify2 store patch "abc-123" {zellij: 5} })]
    $r = $r ++ [(check-err "a mistyped core field is rejected" "must be a string" {||
        agent-notify2 store patch "abc-123" {name: 42} })]
    $r = $r ++ [(check "a rejected write leaves nothing behind"
                       (agent-notify2 store get "no-client") null)]

    # ── opaque ids ───────────────────────────────────────────────────────────
    agent-notify2 store patch "../../etc/passwd" {client: "evil", state: "idle"}
    let escaped = ls ($"($TMP)/agent-notify2/agents/*.json" | into glob) | get name | path basename
    $r = $r ++ [(check "a traversing id cannot escape the store"
                       ($escaped | any {|f| $f | str contains ".." }) false)]
    $r = $r ++ [(check "no id can produce a hidden (unlistable) file"
                       ($escaped | any {|f| $f | str starts-with "." }) false)]
    $r = $r ++ [(check "an awkward id is still readable by id"
                       (agent-notify2 store get "../../etc/passwd" | get client) "evil")]
    agent-notify2 store patch "a/b" {client: "x", state: "idle"}
    agent-notify2 store patch "a_b" {client: "y", state: "idle"}
    $r = $r ++ [(check "ids that v1 would collide stay distinct"
                       [(agent-notify2 store get "a/b" | get client) (agent-notify2 store get "a_b" | get client)]
                       ["x" "y"])]

    # ── list, set, drop ──────────────────────────────────────────────────────
    $r = $r ++ [(check "list sees every record" (agent-notify2 store list | length) 4)]
    let s = agent-notify2 store set "abc-123" {client: "claude", state: "idle"}
    $r = $r ++ [(check "set replaces rather than merges"
                       ("zellij" in ($s.after | columns)) false)]
    $r = $r ++ [(check "drop removes" (agent-notify2 store drop "abc-123") true)]
    $r = $r ++ [(check "drop is idempotent" (agent-notify2 store drop "abc-123") false)]
    $r = $r ++ [(check "dropped records are gone" (agent-notify2 store get "abc-123") null)]

    # ── no litter ────────────────────────────────────────────────────────────
    let tmps = ls ($"($TMP)/agent-notify2/agents/*" | into glob) | get name | where {|f| $f | str ends-with ".tmp" }
    $r = $r ++ [(check "atomic writes leave no temp files" ($tmps | length) 0)]

    # ── the empty store ──────────────────────────────────────────────────────
    # A glob that matches nothing is an ERROR in nushell, and a store whose last
    # agent has just ended is exactly that: the directory outlives its contents.
    agent-notify2 store list | get id | each {|id| agent-notify2 store drop $id } | ignore
    $r = $r ++ [(check "an emptied store lists as nothing, not an error"
                       (agent-notify2 store list) [])]

    summarise $r --title "store"
}
