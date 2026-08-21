# gg — my git superset. Manages whole projects (a GitLab group / GitHub org as a
# fleet of repos) AND authors changes to the current repo, under one roof.
# Uses `glab` / `gh` for fleet ops and the standalone `ai` module for generated
# content.
#
# Command surface
#   Current-repo authoring (forge/, AI-assisted — flattened to top level):
#     gg commit                    — commit staged changes (generated message)
#     gg mr <src> <tgt>            — open a GitLab merge request
#     gg pr <src> <tgt>            — open a GitHub pull request
#   Fleet management:
#     gg gitlab list  <group>      — list repos in a group
#     gg gitlab clone <group>      — clone the group, mirroring the tree
#     gg github list  <org>        — list repos in an org
#     gg github clone <org>        — clone the org, mirroring the tree
#     gg status / each             — (later steps) operate on the whole fleet
#
# Layout
#   One command per file (`export def main`). `forge/` = authoring (flattened).
#   `providers/` = API-backed fleet commands. `lib/` = internal helpers imported
#   by relative path. Agnostic fleet verbs will live under `fleet/`. Generation
#   lives in the sibling `ai` module. See ROADMAP.md.

export use forge *
export use providers/gitlab/
export use providers/github/

# Agnostic fleet verbs land here in later steps (flattened to top level):
# export use fleet *
