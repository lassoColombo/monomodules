# The surfaces: the things that SHOW the store. Clients write, surfaces read.
#
# A surface is one file and four exports, mirroring the client contract in
# `clients/`:
#
#   INFO      what it is, for `agent-notify2 surfaces`
#   settings  strict: validate this surface's namespace from the config file,
#             fill in its defaults, and gather whatever else it needs to know —
#             `me` (the agent this event is about, handed down by dispatch) and
#             anything the environment can tell it. Gathering it all HERE is what
#             lets `project` stay pure enough to run twice.
#   project   PURE: (records, settings) → what should be on screen. Run twice per
#             event, once against the store as it was and once as it is, so that a
#             surface whose output would not change is never touched at all.
#   apply     (desired, settings) → the side effect. The only part that needs
#             zellij or a bar to be installed. It may RETURN a record of facts it
#             learned about this agent, which dispatch records in the store.
#
# TWO RULES, both of which cost real time when broken:
#
# 1. A SURFACE NEVER WRITES THE STORE. It reports; `core/dispatch.nu` records.
#    That keeps "the store is the core, surfaces read it" true without exception,
#    and it keeps a surface out of the store's import cone — see rule 2.
#
# 2. A SURFACE IS A LEAF OF THE IMPORT TREE. nushell parses a module ONCE PER
#    IMPORT PATH, so a module reached both directly and through a surface is
#    parsed twice, on every event. Measured: the store reached through both paths
#    cost 4.51ms where the two alone cost 3.57ms (plan.md §10). Keep the cone a
#    tree, not a diamond.
#
# A new surface is one file plus one entry in `core/dispatch.nu`'s `shipped`
# table, because nushell has no first-class modules and a name cannot be turned
# into a module at runtime.
#
#   zellij.nu   pane titles — the first one, and the smallest useful one
#
# Step 5 adds SketchyBar. `tests/fake.nu` is a complete surface too, and exists so
# the contract can be exercised with nothing at all installed.
