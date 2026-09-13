# The rename — applied

Agreed and carried out on 2026-09-13, before session-containers are designed.
Every name below is LOCKED; this file was the input to the rename and is kept
only until plan.md has been read once in the new vocabulary. Then it goes: the
design lock is plan.md, and two files saying the same thing is one too many.

Two rules came out of the review and are worth keeping for anything new:

1. **No symbolic names.** `janitor`, `surface`, `clock`, `identity` name the
   concept by allusion. A name says what the thing IS.
2. **Name the subject.** Not `verdict` but `display-verdict`; not `discover` but
   `discover-own-location`. A bare verb or a bare abstract noun is a name that
   has not finished.

## The table

| # | now | after | what it is |
|---|-----|-------|-----------|
| 1 | `store`, `core/store.nu` | `session-store`, `core/session-store.nu` | one JSON file per agent session. CLI verb is `session-store` too: `agent-notify session-store get\|list\|patch\|set\|end\|sweep` |
| 2 | `surface`, `surfaces:` | `display`, `displays:` | an external UI the store is pushed to |
| 3 | `janitor`, `core/janitor.nu` | `store-garbage-collector` | finds sessions whose process is gone |
| 4 | `identity`, `core/identity.nu` | `current-session` | which session am I? |
| 5 | `clock`, `core/clock.nu` | `prune-daemon` | the launchd job that prunes periodically |
| 6 | `reap` | `expire-ended-sessions` | deletes `ended/` records older than 7 days |
| 7 | `shipped` / `known` | `integration-registry` / `integration-registry-names` | the hand-written table of built-in integrations |
| 8 | `verdict` | `display-verdict` | one display's repaint outcome: action, wrote, undid, why |
| 9 | `drive` | `event-loop` | the picker's key/redraw loop |
| 10 | `BEAT` / `QUICK` | `REFRESH_EVERY` / `KEY_TIMEOUT` | picker poll intervals |
| 11 | `settle` / `narrow` | `keep-in-view` / `filter` | |
| 12 | `picker/frame.nu`, `CHROME` | `picker/layout.nu`, `NON_LIST_LINES` | |
| 13 | `chip` / `sentinel` / `pool-args` | `item-name` / `exit-item` / `preallocate-args` | SketchyBar item naming |
| 14 | `core/markdown.nu`, `plain` | `plain-md` | |
| 15 | `claims` / `place` / `lives` | `owns` / `location-label` / `where` | the locator members |
| 16 | `core/schema.nu` | `core/session-schema.nu` | |
| 17 | `core/payload.nu` | `core/hook-input.nu` | reads the hook's JSON off stdin |
| 18 | `core/event.nu` | `core/operation.nu` | the write path |
| 19 | the `op` field | `operation-kind` | |
| 20 | `map` (clients) | `to-operation` | hook event + payload -> an operation |
| 21 | `project` / `apply` | `render-items` / `push-items` | records -> a map of name -> desired value, then write it out. The *where* is the module |
| 22 | `observe` | `discover-own-location` | what this process can see about where IT runs |
| 23 | `section`, `HALVES` | `settings-for`, `TOOL_SECTIONS`; halves become `display:` / `commands:` | |
| 24 | `INFO` | keep | |
| 25 | `wiring` | `help-setup` | |
| 26 | `BOOKKEEPING` | `STAMPED_FIELDS` | fields the store stamps, excluded from the change comparison |
| 27 | `semantic` / `durable` | `comparable-fields` / `session-fields` | the compared part / the part that survives being filed away |
| 28 | `s`, `v`, `d`, `f`, `rec`, `recs` | `settings`, `record`, `records`, `delta`, … | expand EVERY one-letter parameter |
| 29 | `known` (two meanings) | `integration-registry-names` / `stored` | |
| 30 | `view` (picker) | keep | free, because surfaces became displays |
| 31 | `drop` / `archive` / `restore` / `prune` / `reap` | `end-session` / `ended/` / `reopen-session` / `sweep-dead-sessions` / `expire-ended-sessions` | one spine for one lifecycle, and each one names its subject |
| 32 | `clients/`, `integrations/` | keep both | `clients/` write, `integrations/` read. Only the config key `surfaces:` moves, to `displays:` |
| 33 | the `v` field | `schema_version` | a ONE-SHOT migration over the live `agents/*.json` and `ended/*.json`, run by hand at rename time. No `migrate` command survives it |

## Not settled here

`zz`, `gg`, `telescope` — the sibling monomodules are cryptic in the same way.
Out of scope on purpose; a separate sweep.

## What the language decided, not us

Three names in the table could not survive contact with nushell, and one more
turned out to be incomplete. All four are settled below, and the table above is
the only place they differ from what shipped.

- **`lives` → `where` was impossible.** `where` is a PARSER KEYWORD, so
  `export def where` is rejected outright — "parser keywords cannot be shadowed
  (including via module exports)". The locator's third question was folded into
  the second: a locator now answers `owns`, `location-label`, `go`.
- **`narrow` → `filter` is legal but shadows the builtin** for the whole of
  `picker/rows.nu`, which is why everything else in that file reaches for
  `where`. The name stands — callers say `rows filter` — and the trap is written
  down at the definition rather than left to be discovered.
- **Module constants cannot be reached through a dashed module name.**
  `$session-schema.STATES` does not parse, because `$session-schema` is not a
  variable name. Where a module's CONSTANT was read through its name, the
  constant is now imported directly (`use ../../core/session-schema.nu STATES`,
  then `$STATES`). The commands are unaffected: `session-schema validate` is a
  command path, not a variable.
- **The operation kind `"drop"` joined the spine as `"end"`** (#31 reached
  further than the table said): the CLI verb, the store function, the operation
  kind and the directory now all say the same word.

## What moved on disk, and what has to be done by hand

`migrate-once.nu` carries the two changes that live outside this repo, and is
deleted once it has run:

1. every record's `v` → `schema_version`, in `agents/` and in `ended/`;
2. the config file's `surfaces:` → `displays:` and each tool's `surface:` →
   `display:` — TEXTUALLY, because that file is mostly commentary and
   `open | to yaml | save` would delete every line of it.

One thing it deliberately does NOT do, because it is a running job rather than a
file: the launchd label changed from `com.agent-notify.clock` to
`com.agent-notify.prune-daemon`. The old job has to be evicted with the old
code, or by hand:

    launchctl bootout gui/$(id -u)/com.agent-notify.clock
    rm ~/Library/LaunchAgents/com.agent-notify.clock.plist
    nu -c 'use agent-notify; agent-notify prune-daemon install'
