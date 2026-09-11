# The store's command surface — which, under plan.md P5, is a PUBLIC API rather
# than a debug tool. Any agent must be able to report, and the way a foreign
# process does that is by running a command, so this layer exists to make the
# store reachable from something that is not nushell:
#
#   from nushell        agent-notify2 store patch abc {state: working}
#   from anything else  echo '{"state":"working"}' \
#                         | nu -c 'use agent-notify2; agent-notify2 store patch abc --stdin'
#
# `--stdin` is explicit rather than inferred, so a command typed by hand with no
# arguments can never hang waiting on a terminal that will send nothing.
#
# Output is nushell values. A foreign caller appends `| to json`, which is both
# the idiomatic answer and one less flag to keep working.
#
# The names here are MULTI-WORD on purpose ("store get", not "get"). A def named
# after a builtin shadows it for every module the file imports — see the note in
# core/store.nu — but a subcommand name is exempt, so the public verbs can be the
# obvious ones while the library underneath uses `read`/`remove`. mod.nu imports
# this file with `*` so the names arrive unprefixed and read as
# `agent-notify2 store get`.
#
# Thin on purpose: everything here is a wrapper. The semantics live in
# core/store.nu, which stays free of any notion of a command line.

use ../core/janitor.nu
use ../core/store.nu *
use ../core/event.nu

def body [given: any, stdin: bool]: nothing -> record {
    if $stdin {
        if ($given != null) {
            error make --unspanned {msg: "agent-notify: pass a record or --stdin, not both"}
        }
        return (open --raw /dev/stdin | from json)
    }
    if ($given == null) {
        error make --unspanned {msg: "agent-notify: no changes given — pass a record, or --stdin to read JSON"}
    }
    $given
}

# One agent's record, or nothing when unknown.
@search-terms agent notify store record
@example "read a record" { agent-notify2 store get 6923c0bc }
export def "store get" [id: string]: nothing -> any { read $id }

# Every agent on record, live or not — liveness is the janitor's business.
@search-terms agent notify store all
export def "store list" []: nothing -> list<any> { list }

# Merge changes into an agent's record, creating it when absent.
#
# Merging is deep, so an owner writes one field of its own namespace without
# reading the rest; a null value deletes its key. The return value says whether
# anything actually moved — `changed: false` means nothing was written at all.
@search-terms agent notify store write update merge
@example "report a state change" { agent-notify2 store patch abc {client: "claude", state: "working"} }
@example "update one namespaced field" { agent-notify2 store patch abc {zellij: {tab_id: 4}} }
@example "delete a field" { agent-notify2 store patch abc {message: null} }
export def "store patch" [
    id: string          # the reporting agent's own id — opaque, any shape
    changes?: record    # what to merge; omit and pass --stdin to read JSON instead
    --stdin             # read the changes as a JSON object on standard input
]: nothing -> record {
    # Through `core/event.nu`, not straight at the store: a write typed here — or
    # sent by a foreign agent, which under P5 is the SAME thing — must reach the
    # surfaces exactly as a hook's write does, or the store and the screen start
    # disagreeing depending on who wrote last.
    event apply {op: "patch", id: $id, changes: (body $changes $stdin)}
}

# Replace an agent's record wholesale — the escape hatch for a client rebuilding
# its own state from scratch. Prefer `store patch`.
@search-terms agent notify store replace overwrite
export def "store set" [
    id: string
    record?: record
    --stdin
]: nothing -> record {
    event apply {op: "set", id: $id, record: (body $record $stdin)}
}

# Forget an agent. Returns whether there was anything to forget.
@search-terms agent notify store delete forget
export def "store drop" [id: string]: nothing -> bool {
    event apply {op: "drop", id: $id} | get changed
}

# Forget every agent that is provably gone: its recorded process is no longer
# running (core/proc.nu), or `/clear` left it behind in a process that has since
# moved on. Prints what it removed and why.
#
# Records with no recorded process are never touched — not knowing that an agent
# is dead is not the same as knowing that it is. See core/janitor.nu.
@search-terms agent notify store prune clean stale dead gc janitor
@example "clean up agents that were killed" { agent-notify2 store prune }
export def "store prune" []: nothing -> table { janitor prune }
