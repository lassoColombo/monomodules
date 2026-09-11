# How an agent's payload reaches us — the one part of a client that is pure
# mechanics, so no client has to write it twice.
#
# There is no single answer, which is why this file exists. Of the agents
# surveyed: Claude Code, Gemini CLI, Cursor and Goose write JSON to STDIN; Codex
# appends JSON as a single ARGV element to whatever program its `notify` names;
# Aider runs a bare command with no payload at all. A client picks its reader in
# one line and gets on with the interesting part.

# JSON on stdin, the common case.
#
# GUARDED, because reading stdin blocks until the writer closes it: an entry point
# run by hand in a terminal would otherwise hang with no clue why. A hook always
# has a body and the agent closes the pipe; a human typing the command gets an
# empty record instead of a stuck shell.
#
# A body that will not parse is not an exception either — an empty record carries
# no identity, which every client's `map` already treats as "ignore".
export def from-stdin []: nothing -> record {
    if (is-terminal --stdin) { return {} }
    let parsed = try { open --raw /dev/stdin | from json } catch { {} }
    if (($parsed | describe) | str starts-with "record") { $parsed } else { {} }
}

# JSON as one of our own arguments — Codex's `notify` appends it to the argv of
# the program it was told to run. The first argument that parses as a JSON object
# wins, so it does not matter where the agent chose to put it.
export def from-args [args: list<string>]: nothing -> record {
    for a in $args {
        let parsed = try { $a | from json } catch { null }
        if (($parsed | describe) | str starts-with "record") { return $parsed }
    }
    {}
}
