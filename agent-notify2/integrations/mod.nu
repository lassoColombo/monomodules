# The integrations: the other programs this module knows how to work with.
# Clients WRITE the store; integrations read it.
#
# AN INTEGRATION HAS TWO HALVES, and they are not the same kind of thing. That is
# the whole reason this directory is called `integrations/` and not `surfaces/`
# (plan.md D47):
#
#   PUSH — its SURFACE. Something already on screen, kept in sync as events
#          arrive: pane and tab titles, bar counters. It is driven by dispatch,
#          switched on by `surfaces:` in the config file, and configured under
#          that tool's `surface:` key.
#
#   PULL — its COMMANDS. Something you invoke: the picker, the jump. Nothing
#          turns them on, because you ran them. Configured under `commands:`.
#
#   integrations/
#     zellij/
#       mod.nu      PUSH   pane and tab titles
#       browse.nu   PULL   the picker
#       jump.nu     PULL   go to an agent's pane
#     sketchybar/
#       mod.nu      PUSH   counters, drawers and hover previews
#       items.nu           item names, the fixed pool, the generated shell
#       text.nu            markdown → what a label can show
#
# The halves are separate FILES, not just separate exports, and that is load
# bearing: the push half is in the HOT cone of every hook, and the pull half must
# never be. `core/dispatch.nu` imports `mod.nu`; the CLI imports the others. A
# command that dragged skim into the hook's import cone would be paid for on
# every tool call, forever.
#
# ── THE SURFACE CONTRACT ─────────────────────────────────────────────────────
# A surface DESCRIBES; `core/dispatch.nu` DECIDES; the store holds the facts. A
# surface never works out what changed — it says what should be shown, and
# dispatch diffs two of those answers.
#
#   INFO      what it is, for `agent-notify2 surfaces`
#   settings  strict: validate the `surface` half of this tool's namespace, fill
#             in its defaults, and resolve any program it calls to an ABSOLUTE
#             path. Settings only — nothing about the world.
#   observe   OPTIONAL: (known, settings) → what this process can see about ITSELF
#             that the store does not know yet — which pane and tab it is in, say.
#             `known` is what the store already holds for this surface, so a
#             lookup already paid for is not repeated. Dispatch records the answer
#             in this surface's own namespace, which is what lets `project` stay a
#             plain function of records.
#   project   PURE: (records, settings) → a MAP of key → what that key should
#             show. Run against the store as it was and as it is; dispatch diffs
#             the two.
#   apply     (changed, removed, settings) → the side effect, and the only part
#             that needs zellij or a bar installed. `removed` carries each key's
#             OLD value, because undoing needs to know what was there.
#
# A new surface is one file plus one entry in `core/dispatch.nu`'s `shipped`
# table, because nushell has no first-class modules and a name cannot be turned
# into a module at runtime. A new COMMAND is one file plus one line in the
# facade — no table, because nothing dispatches to it.
#
# ── THREE RULES, each of which cost real time when broken ────────────────────
#
# 1. A SURFACE NEVER WRITES THE STORE. It describes and it reports; dispatch
#    records. That keeps "the store is the core, integrations read it" true
#    without exception, and keeps a surface out of the store's import cone — see
#    rule 2. Commands are not bound by this: a jump changes nothing, but a future
#    command that does would write through `core/event.nu`, like the CLI does.
#
# 2. A SURFACE IS A LEAF OF THE IMPORT TREE. nushell parses a module ONCE PER
#    IMPORT PATH, so a module reached both directly and through a surface is
#    parsed twice, on every event. Measured: the store reached both ways cost
#    4.51ms where the two alone cost 3.57ms (plan.md §10). A tool's own pull half
#    is NOT an exception waiting to happen — it is a different file, so it is a
#    different path, and the hook never reaches it.
#
# 3. A SIDE EFFECT IS BUILT AS DATA FIRST. `message` for the bar, `commands` for
#    zellij: pure functions returning what would be sent, with `apply` a couple of
#    lines that send it. Both suites then run with nothing installed and not one
#    subprocess, asserting the exact arguments.
#
# `tests/fake.nu` is a complete surface too, and exists so the contract can be
# exercised with nothing at all installed.
