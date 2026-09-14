# The session-store's command set — which, under plan.md P5, is a PUBLIC API
# rather than a debug tool. Any agent must be able to report, and the way a
# foreign process does that is by running a command, so this layer exists to
# make the session-store reachable from something that is not nushell:
#
#   from nushell        agent-notify session-store patch abc {state: working}
#   from anything else  echo '{"state":"working"}' \
#                         | nu -c 'use agent-notify
#                                   agent-notify session-store patch abc --stdin'
#
# `--stdin` is explicit rather than inferred, so a command typed by hand with no
# arguments can never hang waiting on a terminal that will send nothing.
#
# Output is nushell values. A foreign caller appends `| to json`, which is both
# the idiomatic answer and one less flag to keep working.
#
# The names here are MULTI-WORD on purpose ("session-store get", not "get"). A
# def named after a builtin shadows it for every module the file imports — see
# the note in core/session-store.nu — but a subcommand name is exempt, so the
# public verbs can be the obvious ones while the library underneath uses
# `read`/`remove`. mod.nu imports
# this file with `*` so the names arrive unprefixed and read as
# `agent-notify session-store get`.
#
# Thin on purpose: everything here is a wrapper. The semantics live in
# core/session-store.nu, which stays free of any notion of a command line.

use ../core/store-garbage-collector.nu
use ../core/session-store.nu *
use ../core/session-change.nu

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
@search-terms agent notify session-store record
@example "read a record" { agent-notify session-store get 6923c0bc }
export def "session-store get" [id: string]: nothing -> any { read $id }

# Every agent that is running. `--ended` shows the other directory instead: the
# sessions that have stopped and not yet been reaped, newest write last.
#
# "Running" here means "has not ended", not "provably alive" — proving an agent
# dead is the store-garbage-collector's business (`session-store sweep`).
@search-terms agent notify session-store all list ended history resumable
@example "what is running?" { agent-notify session-store list }
@example "…and what has ended?" { agent-notify session-store list --ended }
export def "session-store list" [
    --ended     # the archive instead: sessions that have stopped
]: nothing -> list<any> {
    if $ended { ended } else { list }
}

# Merge changes into an agent's record, creating it when absent.
#
# Merging is deep, so an owner writes one field of its own namespace without
# reading the rest; a null value deletes its key. The return value says whether
# anything actually moved — `changed: false` means nothing was written at all.
@search-terms agent notify session-store write update merge
@example "report a state change" { agent-notify session-store patch abc {agent: "claude", state: "working"} }
@example "update one namespaced field" { agent-notify session-store patch abc {zellij: {tab_id: 4}} }
@example "delete a field" { agent-notify session-store patch abc {message: null} }
export def "session-store patch" [
    id: string          # the reporting agent's own id — opaque, any shape
    changes?: record    # what to merge; omit and pass --stdin to read JSON instead
    --stdin             # read the changes as a JSON object on standard input
]: nothing -> record {
    # Through `core/session-change.nu`, not straight at the session-store: a
    # write typed here — or sent by a foreign agent, which under P5 is the SAME
    # thing — must reach the displays exactly as a hook's write does, or the
    # session-store and the screen start disagreeing depending on who wrote
    # last.
    session-change apply {change-kind: "patch", id: $id, changes: (body $changes $stdin)}
}

# Replace an agent's record wholesale — the escape hatch for an agent rebuilding
# its own state from scratch. Prefer `session-store patch`.
@search-terms agent notify session-store replace overwrite
export def "session-store set" [
    id: string
    record?: record
    --stdin
]: nothing -> record {
    session-change apply {change-kind: "set", id: $id, record: (body $record $stdin)}
}

# The agent has stopped. Takes it off every display and FILES ITS RECORD AWAY —
# it is not destroyed, so resuming that session brings its name back
# (core/session-store.nu). Returns whether there was anything to file.
@search-terms agent notify session-store delete forget end drop
export def "session-store end" [id: string]: nothing -> bool {
    session-change apply {change-kind: "end", id: $id} | get changed
}

# File away every agent that is provably gone: its recorded process is no longer
# running (core/agent-process.nu), or `/clear` left it behind in a process that
# has since moved on. Prints what it took off the displays, and why.
#
# Records with no recorded process are never touched — not knowing that an agent
# is dead is not the same as knowing that it is. See
# core/store-garbage-collector.nu.
@search-terms agent notify session-store sweep clean stale dead gc store-garbage-collector
@example "clean up agents that were killed" { agent-notify session-store sweep }
export def "session-store sweep" []: nothing -> table {
    store-garbage-collector sweep-dead-sessions | select id agent state why
}
