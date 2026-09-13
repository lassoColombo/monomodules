# How an agent's payload reaches us — the one part of an agent module that is
# pure mechanics, so no agent module has to write it twice.
#
# STDIN JSON is what every integration-registry agent uses, and what the survey
# found nearly everywhere: Claude Code, Codex hooks, Gemini CLI, Cursor and
# Goose all write one JSON object to a hook's stdin. The exceptions need no help
# from here — Codex's older `notify` appended JSON as an argv element (one `from
# json` in the agent module that wants it), and Aider passes nothing at all, so its
# module would have to invent a session id rather than read one.

# GUARDED, because reading stdin blocks until the writer closes it: an entry
# point run by hand in a terminal would otherwise hang with no clue why. A hook
# always has a body and the agent closes the pipe; a human typing the command
# gets an empty record instead of a stuck shell.
#
# A body that will not parse is not an exception either — an empty record
# carries no current-session, which every agent module's `map` already treats as
# "ignore".
export def from-stdin []: nothing -> record {
    if (is-terminal --stdin) { return {} }
    let parsed = try { open --raw /dev/stdin | from json } catch { {} }
    if (($parsed | describe) | str starts-with "record") { $parsed } else { {} }
}
