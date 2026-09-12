# The surfaces: the things that SHOW the store. Clients write, surfaces read.
#
# THE DIVISION OF LABOUR. A surface DESCRIBES; `core/dispatch.nu` DECIDES; the
# store holds the facts. A surface never works out what changed — it says what
# should be shown, and dispatch diffs two of those answers.
#
#   INFO      what it is, for `agent-notify2 surfaces`
#   settings  strict: validate this surface's namespace from the config file, fill
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
# THREE RULES, each of which cost real time when broken:
#
# 1. A SURFACE NEVER WRITES THE STORE. It describes and it reports; dispatch
#    records. That keeps "the store is the core, surfaces read it" true without
#    exception, and keeps a surface out of the store's import cone — see rule 2.
#
# 2. A SURFACE IS A LEAF OF THE IMPORT TREE. nushell parses a module ONCE PER
#    IMPORT PATH, so a module reached both directly and through a surface is
#    parsed twice, on every event. Measured: the store reached both ways cost
#    4.51ms where the two alone cost 3.57ms (plan.md §10).
#
# 3. A SIDE EFFECT IS BUILT AS DATA FIRST. `message` for the bar, `commands` for
#    zellij: pure functions returning what would be sent, with `apply` a couple of
#    lines that send it. Both suites then run with nothing installed and not one
#    subprocess, asserting the exact arguments.
#
# A new surface is one file plus one entry in `core/dispatch.nu`'s `shipped`
# table, because nushell has no first-class modules and a name cannot be turned
# into a module at runtime.
#
#   zellij.nu       pane titles — one key per pane, and it has things to undo
#   sketchybar.nu   three counters — fixed keys, so nothing is ever removed
#
# `tests/fake.nu` is a complete surface too, and exists so the contract can be
# exercised with nothing at all installed.
