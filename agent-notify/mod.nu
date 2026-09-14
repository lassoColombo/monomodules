# agent-notify — agent state as an on-disk session store, and the displays
# rendered from it.
#
# A ground-up rebuild of `ai/agent-notify`, developed beside it as `agent-notify2`
# and promoted over it when finished (D17). The original is deleted; this is the
# module now, one of the monomodules beside `ai` rather than a submodule of it.
# plan.md is the design lock: the principles, the measurements they were tested
# against, and the decisions taken.
#
# The shape, in one paragraph: any agent — Claude Code, another CLI agent, a
# script — reports what it is doing by writing the SESSION-STORE, which is the
# core and the only thing that owns state. Displays (zellij titles, a SketchyBar
# drawer, a terminal picker) are opt-in integrations that read it and render it,
# never the other way round. Everything, logic and graphics alike, lives in this
# module; no glue scripts in anyone else's config directory.
#
# BUILD STATE — complete (plan.md §9). The session-store and its command set,
# the Claude and Codex agents, liveness by process, the config file, dispatch,
# zellij pane and tab titles, the SketchyBar counters with their drawers and
# hover previews, the launchd prune daemon, the jump, and the picker. **v1 was
# dismissed on 2026-09-12** while this was still incomplete, on purpose, and
# DELETED once this was finished: `ai/agent-notify/` is gone, along with its five
# glue scripts in ~/.config/sketchybar/plugins and the one line in sketchybarrc
# that still called into them. Nothing of ours lives in anyone else's config
# directory.
#
# What v1 did, this does — with no skim, no bat and no pandoc anywhere. Every
# step in plan.md §9 is done; what was set aside on purpose is §9b, which is one
# list rather than a comment in each file: a click on a bar row (blocked on the
# window-manager question, not on effort), a palette for the picker, and where
# the bench harness should live.
#
# Turn the displays on with ~/.config/agent-notify/config.yaml. That list is
# what the session-store is PUSHED to; a tool's COMMANDS run because you ran
# them, which is why each tool's settings have two halves (plan.md D47):
#
#   displays: [zellij, sketchybar]
#
#   zellij:
#     binary: zellij         # shared
#     display: {glyphs: …}   # push — how it shows the session-store
#     commands:              # pull — how its commands behave
#       focus_terminal_window: [open, -a, Ghostty]
#
# That last one is the only setting this module has that names a program, and it
# names one because it cannot know one: a jump from the BAR arrives from the
# desktop, so the terminal's window has to come forward before its pane can be
# focused, and which command does that is your terminal's and your window
# manager's business (plan.md D50, D73). Empty by default; a jump from inside
# the terminal never needs it.
#
# The commands, every one of them under `agent-notify`:
#
#   session-store get|list|patch|set|end     the session store itself
#   session-store list --ended               sessions that have ended
#   session-store sweep                      file away agents provably gone
#   report|name                              what an agent says about itself
#   agents [help-setup <name>]               which agents can report, and how
#   config path|show|check                   the settings file
#   displays [refresh|install|help-setup]    what shows it, and repaint them
#   prune-daemon status                      the periodic look for dead agents
#   prune-daemon help-setup <launcher>       …how to set it up, printed
#   browse [query]                           pick a live agent, land in its pane
#   jump <who> [--dry-run]                   …or go straight there, by name or id
#
# The command set is deliberately reachable from outside nushell (plan.md P5):
#
#   echo '{"agent":"claude","state":"working"}' \
#     | nu -c 'use agent-notify; agent-notify session-store patch <id> --stdin'

export use cli/session-store.nu *
export use cli/self-report.nu *
export use cli/agents.nu
export use cli/config.nu *
export use cli/displays.nu
export use cli/prune-daemon.nu *
export use cli/browse.nu
export use cli/jump.nu

# `browse` and `jump` are both up there with the rest, and neither names a tool.
# A picker is not a zellij program and neither is a jump: both ask whichever
# integration CONTAINS an agent where it lives and how to get there
# (`integrations/session-containers.nu`), so a tmux integration adds one file
# and one row in that table and touches neither command (plan.md §4.8, D74).
