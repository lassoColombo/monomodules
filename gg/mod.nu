# gg — my git superset. Manages whole projects (a GitLab group / GitHub org as a
# fleet of repos) AND authors changes to the current repo, under one roof.
#
# Fleet ops read the declared desired state in `$env.gg_config` (see README) and
# use `glab` / `gh`; authoring uses the standalone `ai` module.
#
# Command surface
#   Fleet (config-driven; omit <source> to act on every configured source):
#     gg list  [source]            — list a source's repos (remote enumeration)
#     gg clone [source]            — clone missing repos into the source's dir
#     gg status / each             — (later steps) operate on cloned repos
#   Current-repo authoring (forge/, AI-assisted — flattened to top level):
#     gg commit                    — commit staged changes (generated message)
#     gg mr <src> <tgt>            — open a GitLab merge request
#     gg pr <src> <tgt>            — open a GitHub pull request
#
# Layout
#   One command per file (`export def main`). `fleet/` = fleet verbs (flattened).
#   `forge/` = authoring (flattened). `providers/` + `lib/` = internal helpers
#   imported by relative path (not re-exported). Generation lives in the sibling
#   `ai` module. See ROADMAP.md.

export use fleet *
export use forge *
