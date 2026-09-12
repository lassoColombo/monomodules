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
# BUILD STATE — complete (plan.md §9). The store and its command surface, the
# Claude and Codex clients, liveness by process, the config file, dispatch,
# zellij pane and tab titles, the SketchyBar counters with their drawers and
# hover previews, the launchd clock, the jump, and the picker. **v1 was dismissed
# on 2026-09-12** while this was still incomplete, on purpose, and DELETED once
# this was finished: `ai/agent-notify/` is gone, along with its five glue scripts
# in ~/.config/sketchybar/plugins and the one line in sketchybarrc that still
# called into them.
#
# What v1 did, this does — with no skim, no bat and no pandoc anywhere. Left
# over: settling D17 (the promoted name), a palette for the picker, and making a
# click on a bar row jump too.
#
# Turn the surfaces on with ~/.config/agent-notify/config.yaml. That list is what
# the store is PUSHED to; a tool's COMMANDS run because you ran them, which is
# why each tool's settings have two halves (plan.md D47):
#
#   surfaces: [zellij, sketchybar]
#
#   zellij:
#     binary: zellij         # shared
#     surface: {glyphs: …}   # push — how it shows the store
#     commands: {}           # pull — how its commands behave
#
#   agent-notify2 store get|list|patch|set|drop     the store itself
#   agent-notify2 store prune                      forget agents that are provably gone
#   agent-notify2 report|name                       what an agent says about itself
#   agent-notify2 clients [wiring <name>]           which agents can report, and how
#   agent-notify2 config path|show|check            the settings file
#   agent-notify2 surfaces [refresh|install|wiring] what shows the store, and repaint
#   agent-notify2 clock install|status              the periodic look for dead agents
#   agent-notify2 browse [query]                    pick a live agent, land in its pane
#   agent-notify2 jump <who>                        …or go straight there, by name or id
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
export use cli/clock.nu *
export use cli/browse.nu

# The PULL half of an integration: commands, not a surface. Nothing dispatches to
# them and `surfaces:` does not turn them on — see integrations/mod.nu.
#
# `browse` is NOT here, and that is the shape of it: a picker is not a zellij
# program. It asks whichever integration claimed an agent where it lives and what
# is on its screen (`picker/locators.nu`), so it sits with the other commands and
# a tmux integration would never touch it. A jump genuinely is zellij's, and
# stays here.
export use integrations/zellij/jump.nu
