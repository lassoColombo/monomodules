# agent-notify2 — agent state as an on-disk store, and surfaces projected from it.
#
# A ground-up rebuild of `ai/agent-notify`, developed beside it and promoted over
# it when finished. plan.md is the design lock: the principles, the measurements
# they were tested against, and the decisions already taken.
#
# The shape, in one paragraph: any agent — Claude Code, another CLI agent, a
# script — reports what it is doing by writing the STORE, which is the core and
# the only thing that owns state. Surfaces (zellij titles, a SketchyBar drawer, a
# terminal picker) are opt-in integrations that read it and project it, never the
# other way round. Everything, logic and graphics alike, lives in this module; no
# glue scripts in anyone else's config directory.
#
# BUILD STATE — step 5 of 7 (see plan.md §9). The store, its command surface, the
# Claude and Codex clients, the config file, the dispatch gate, the zellij pane
# titles and the SketchyBar counters all exist. Turn them on with a config file:
#
#   surfaces: [zellij, sketchybar]
#
#   agent-notify2 store get|list|patch|set|drop     the store itself
#   agent-notify2 store prune                      forget agents that are provably gone
#   agent-notify2 report|name                       what an agent says about itself
#   agent-notify2 clients [wiring <name>]           which agents can report, and how
#   agent-notify2 config path|show|check            the settings file
#   agent-notify2 surfaces [refresh|install|wiring] what shows the store, and repaint
#
# The command surface is deliberately reachable from outside nushell (plan.md P5):
#
#   echo '{"client":"claude","state":"working"}' \
#     | nu -c 'use agent-notify2; agent-notify2 store patch <id> --stdin'

export use cli/store.nu *
export use cli/agent.nu *
export use cli/clients.nu
export use cli/config.nu *
export use cli/surfaces.nu
