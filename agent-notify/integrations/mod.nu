# The integrations: the other programs this module knows how to work with.
# Clients WRITE the session-store; integrations read it.
#
# AN INTEGRATION HAS TWO TOOL_SECTIONS, and they are not the same kind of thing.
# That is the whole reason this directory is called `integrations/` and not
# `displays/` (plan.md D47):
#
#   PUSH — its DISPLAY. Something already on screen, kept in sync as events
#          arrive: pane and tab titles, bar counters. It is driven by dispatch,
#          switched on by `displays:` in the config file, and configured under
#          that tool's `display:` key.
#
#   PULL — its COMMANDS, and what the PICKER needs from it. Nothing turns these
#          on, because you ran them. Configured under `commands:`.
#
#   integrations/
#     zellij/
#       mod.nu      PUSH   pane and tab titles
#       jump.nu     PULL   go to an agent's pane
#       locate.nu   PULL   where an agent lives, and how to go there
#     sketchybar/
#       mod.nu      PUSH   counters, drawers and hover previews
#       items.nu           item names, the fixed pool, the generated shell —
#                          and that shell's escaping, at the point of quoting
#
# The markdown a message is written in is flattened by `core/markdown.nu`, which
# was `sketchybar/text.nu` until the picker's preview became its second reader.
#
# THE PICKER IS NOT IN HERE, and that is the shape of it. `agent-notify browse`
# lives in `cli/` with the other commands, and the machinery in `picker/`,
# because a picker is not a zellij program: it asks whichever integration
# claimed an agent the three questions in `locate.nu` and draws the answers. A
# tmux integration is one more `locate.nu` and one more row in
# `picker/locators.nu` — and not one line of the picker changes.
#
# The halves are separate FILES, not just separate exports, and that is load
# bearing: the push half is in the HOT cone of every hook, and the pull half
# must never be. `core/dispatch.nu` imports `mod.nu`; the CLI imports the
# others. A pull half that reached the hook's import cone would be parsed on
# every tool call, forever — and `locate.nu` drags `jump.nu` and the config in
# behind it.
#
# ── THE DISPLAY CONTRACT ──────────────────────────────────────────────────────
# A display DESCRIBES; `core/dispatch.nu` DECIDES; the session-store holds the
# facts. A display never works out what changed — it says what should be shown,
# and dispatch diffs two of those answers.
#
#   INFO          what it is, for `agent-notify displays`
#   settings      strict: validate the `display` half of this tool's namespace,
#                 fill in its defaults, and resolve any program it calls to an
#                 ABSOLUTE path. Settings only — nothing about the world.
#   discover-own-location
#                 OPTIONAL: (stored, settings) → what this process can see about
#                 ITSELF that the store does not know yet — which pane and tab it
#                 is in, say. `stored` is what the store already holds for this
#                 display, so a lookup already paid for is not repeated. Dispatch
#                 records the answer in this display's own namespace, which is
#                 what lets `render-items` stay a plain function of records.
#   render-items  PURE: (records, settings) → a MAP of key → what that key should
#                 show. Run against the store as it was and as it is; dispatch
#                 diffs the two.
#   push-items    (changed, removed, settings) → the side effect, and the only
#                 part that needs zellij or a bar installed. `removed` carries
#                 each key's OLD value, because undoing needs to know what was
#                 there.
#
# A new display is one file plus one entry in `core/dispatch.nu`'s
# `integration-registry` table, because nushell has no first-class modules and a
# name cannot be turned into a module at runtime. A new COMMAND is one file plus
# one line in the facade — no table, because nothing dispatches to it.
#
# ── THE LOCATOR CONTRACT ──────────────────────────────────────────────────────
# The same idea for the picker, and the same hand-written table, in
# `picker/locators.nu`:
#
#   INFO            what it is
#   owns            is this record yours?    it has a `zellij` namespace
#   location-label  where does it live?      home/root
#   go              take me there            `jump`
#
# There was a `screen` — dump me this agent's live terminal — and step 8 took it
# out with the preview that needed it (D58). The picker shows the stored message
# now, which every record has, so a locator asks only what the multiplexer alone
# can answer.
#
# Which locator answers is decided by the RECORD, not by the config file:
# `displays:` says what the session-store is pushed to and nothing else (D47), so
# switching the zellij display off must not stop the picker taking you to a
# zellij pane. `tests/fake.nu` ships a fake locator beside the fake display, which
# is how the whole picker is asserted with neither zellij nor tmux installed.
#
# ── THREE RULES, each of which cost real time when broken ─────────────────────
#
# 1. A DISPLAY NEVER WRITES THE SESSION-STORE. It describes and it reports;
#    dispatch records. That keeps "the store is the core, integrations read it"
#    true without exception, and keeps a display out of the store's import cone —
#    see rule 2. Commands are not bound by this: a jump changes nothing, but a
#    future command that does would write through `core/operation.nu`, like the
#    CLI does.
#
# 2. A DISPLAY IS A LEAF OF THE IMPORT TREE. nushell parses a module ONCE PER
#    IMPORT PATH, so a module reached both directly and through a display is
#    parsed twice, on every event. Measured: the store reached both ways cost
#    4.51ms where the two alone cost 3.57ms (plan.md §10). A tool's own pull half
#    is NOT an exception waiting to happen — it is a different file, so it is a
#    different path, and the hook never reaches it.
#
# 3. A SIDE EFFECT IS BUILT AS DATA FIRST. `message` for the bar, `commands` for
#    zellij: pure functions returning what would be sent, with `push-items` a
#    couple of lines that send it. Both suites then run with nothing installed
#    and not one subprocess, asserting the exact arguments.
#
# `tests/fake.nu` is a complete display too, and exists so the contract can be
# exercised with nothing at all installed.
