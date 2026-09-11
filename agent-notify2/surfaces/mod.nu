# The surfaces: the things that SHOW the store. Clients write, surfaces read.
#
# A surface is one file and four exports, mirroring the client contract in
# `clients/`:
#
#   INFO      what it is, for `agent-notify2 surfaces`
#   settings  strict: validate this surface's namespace from the config file and
#             fill in its defaults. The core never learns a surface's fields.
#   project   PURE: (records, settings) → what should be on screen. Run twice per
#             event, once against the store as it was and once as it is, so that a
#             surface whose output would not change is never touched at all.
#   apply     (desired, settings) → the side effect. The only impure part, and the
#             only part that needs zellij or a bar to be installed.
#
# A new surface is one file plus one entry in `core/dispatch.nu`'s `shipped`
# table, because nushell has no first-class modules and a name cannot be turned
# into a module at runtime.
#
# EMPTY FOR NOW, deliberately. Step 3 built the machinery; step 4 writes the
# zellij surface and step 5 SketchyBar. The contract above is exercised today by
# `tests/fake.nu`, which needs nothing installed to prove the gate works.
