# Where the store lives, and the one genuinely non-obvious thing about it:
# turning an opaque agent id into a filename.
#
# The id belongs to whoever reports (see plan.md P5) — a session uuid from one
# agent, a pid from another, a name from a script. So it may contain anything at
# all, including a `/`, which makes the derivation a correctness concern and not
# a cosmetic one: `../../etc/passwd` must not escape the store directory, and two
# different ids must never land on the same file. v1's mapping does neither — it
# replaces `/` with `_`, so `a/b` and `a_b` collide.
#
# The rule here: an id that is already safe and short IS the filename, so the
# common case (a uuid) stays greppable; anything else keeps a stripped prefix for
# recognisability and takes a hash of the WHOLE id for uniqueness. The mapping is
# one-way on purpose — nothing needs to reverse it, because every record carries
# its own `id` field and that is the truth.

export def xdg-data-home []: nothing -> string {
    if ($env.XDG_DATA_HOME? | is-not-empty) { $env.XDG_DATA_HOME } else { [$env.HOME .local share] | path join }
}

# Everything this module owns on disk. TWO directories, and the split is the
# whole of how a resumed session works:
#
#   agents/   live. The only thing any surface ever reads, so it stays small and
#             `list` stays cheap — measured: 3 records 0.4ms, 600 records 36.9ms,
#             and `list` runs on every event.
#   ended/    filed away. A session that ends is MOVED here, not deleted, and
#             moved back if you resume it.
#
# Keeping ended sessions in `agents/` with a flag would have been the textbook
# soft delete, and the measurement above is why it is not: a month of history
# would put 36ms on every tool call. A directory the hot path never opens costs
# nothing at all.
export def store-root []: nothing -> string { [(xdg-data-home) agent-notify] | path join }

export def agents-dir []: nothing -> string { [(store-root) agents] | path join }
export def ended-dir []: nothing -> string { [(store-root) ended] | path join }

export def ensure-dir [dir: string] { if not ($dir | path exists) { mkdir $dir } }

# Safe = the POSIX portable filename set, which is also what survives a shell, a
# URL and a human reading it aloud. 100 chars leaves room for the ".json" and
# stays far inside every filesystem's limit.
#
# The FIRST character is restricted further, to alphanumeric or underscore, and
# that is not fussiness: an id of `.hidden` — or `../../etc/passwd`, which strips
# to `....etcpasswd` — would otherwise produce a dotfile, and a dotfile is
# invisible to the glob `list` walks. The record would be written, readable by id,
# and absent from every surface. (Found by the step-1 suite, which is the whole
# reason it tries a traversing id.)
const SAFE_ID = '^[A-Za-z0-9_][A-Za-z0-9._-]{0,99}$'

export def encode-id [id: string]: nothing -> string {
    if ($id =~ $SAFE_ID) { return $id }
    # Strip rather than escape: the prefix is only a hint for a human browsing the
    # directory, and the hash — taken over the ORIGINAL id, not the stripped form —
    # is what actually keeps two ids apart.
    let hint = $id
        | str replace --all --regex '[^A-Za-z0-9._-]' ''
        | str replace --regex '^[^A-Za-z0-9_]+' ''
        | str substring 0..40
    let digest = $id | hash sha256 | str substring 0..16
    if ($hint | is-empty) { $digest } else { $"($hint)-($digest)" }
}

export def record-file [id: string]: nothing -> string {
    [(agents-dir) $"(encode-id $id).json"] | path join
}

export def ended-file [id: string]: nothing -> string {
    [(ended-dir) $"(encode-id $id).json"] | path join
}
