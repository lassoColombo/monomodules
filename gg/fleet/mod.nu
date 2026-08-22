# Fleet commands — operate across the configured fleet (see $env.gg_config).
# Flattened to the gg top level (gg list / gg clone / gg each).
#
# ORDER MATTERS: `each.nu` defines a command named `each`, which shadows the
# built-in `each` for every sibling imported AFTER it (nushell resolves a
# module-scoped command over the built-in of the same name). Files here use the
# built-in `each` for plain list mapping, so `each.nu` MUST be imported LAST —
# otherwise their `... | each {…}` silently calls the fleet closure-runner.
export use list.nu
export use clone.nu
export use status.nu
export use sync.nu
export use each.nu   # keep last — see note above
