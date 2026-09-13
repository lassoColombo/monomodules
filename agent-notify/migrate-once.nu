# THE ONE-SHOT, and the only reason this file exists.
#
# The rename (naming.md) changed two things that live on DISK rather than in
# this repo, so no amount of renaming inside the module reaches them:
#
#   1. the stored field `v`        → `schema_version`   (#33)
#   2. the config keys `surfaces:` → `displays:` and each tool's
#      `surface:`                  → `display:`          (#2, #23)
#
# Run it once, when the rename lands. It is idempotent — a record already
# carrying `schema_version` and a config already speaking `displays:` are left
# exactly as they are — so running it twice costs a read and nothing else. Then
# DELETE THIS FILE: a migration that can only ever run once is not a command,
# and keeping it would leave the module with a verb nobody should type.
#
# It is deliberately NOT wired into mod.nu. Nothing imports it, and it is not a
# subcommand, because `agent-notify migrate` would outlive the one morning it
# was useful.
#
#   nu -n --no-std-lib -I . agent-notify/migrate-once.nu
#   nu -n --no-std-lib -I . agent-notify/migrate-once.nu --dry-run

use core/paths.nu *
use core/config.nu

def migrate-record [file: string, --dry-run]: nothing -> record {
    let rec = try { open --raw $file | from json } catch { null }
    if $rec == null { return {file: $file, did: "unreadable"} }
    if (($rec | describe) | str starts-with "record") == false {
        return {file: $file, did: "not a record"}
    }
    if ($rec | get -o v) == null { return {file: $file, did: "already migrated"} }

    # Field order is not semantic in JSON, and the store rewrites the whole
    # record on the next write anyway, so a reject-then-merge is enough.
    let moved = ($rec | reject v | merge {schema_version: ($rec | get v)})
    if not $dry_run { $moved | to json --indent 2 | save --force $file }
    {file: $file, did: "v → schema_version"}
}

# TEXTUALLY, not by `open | to yaml | save`. That round trip parses the file and
# writes back a value, and a YAML value has no comments — it would delete the
# entire file except for eleven lines of settings. This config is mostly
# commentary, including a commented-out copy of every default, and that IS the
# documentation. So: line edits, which also reach the commented examples and the
# prose that names the old commands.
def migrate-config [--dry-run]: nothing -> record {
    let f = config file
    if not ($f | path exists) { return {file: $f, did: "no config file"} }
    let before = try { open --raw $f } catch { null }
    if $before == null { return {file: $f, did: "unreadable"} }

    let after = $before
        | str replace --all --regex '(?m)^surfaces:' 'displays:'
        | str replace --all --regex '(?m)^(#?\s+)surface:' '${1}display:'
        | str replace --all "agent-notify surfaces" "agent-notify displays"
        | str replace --all "what shows the agent store" "what shows the session store"

    if $after == $before { return {file: $f, did: "already migrated"} }
    if not $dry_run {
        cp $f $"($f).bak-rename"
        $after | save --force $f
    }
    {file: $f, did: "surfaces: → displays:, surface: → display: (comments kept)"}
}

def main [--dry-run] {
    let agents = agents-dir
    let ended = ended-dir
    let files = [$agents $ended]
        | where {|d| $d | path exists }
        | each {|d| ls $d | where name =~ '\.json$' | get name }
        | flatten

    let records = $files | each {|f| migrate-record $f --dry-run=$dry_run }
    let cfg = migrate-config --dry-run=$dry_run

    print ($records | append $cfg)
    print $"(if $dry_run { 'WOULD MIGRATE' } else { 'MIGRATED' }) ($files | length) record\(s\) and the config file."
}
