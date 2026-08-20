# gg — manage whole projects (a GitLab group / GitHub org = a fleet of repos),
# not individual repositories. Uses `glab` / `gh` to list & clone, and plain
# `git` to operate on the local fleet.
#
# Command surface
#   Provider-agnostic (local git):
#     gg commit                    — commit staged changes (AI-generated message)
#     gg status / update / each    — (later steps) operate on the whole fleet
#   GitLab (via glab):
#     gg gitlab list  <group>      — list repos in a group
#     gg gitlab clone <group>      — clone the group, mirroring the tree
#     gg gitlab mr    <src> <tgt>  — open a merge request for the cwd repo
#   GitHub (via gh):
#     gg github list  <org>        — list repos in an org
#     gg github clone <org>        — clone the org, mirroring the tree
#     gg github pr    <src> <tgt>  — open a pull request for the cwd repo
#
# Layout
#   Leaf commands are one-per-file (`export def main`). `lib/` holds internal
#   helpers imported by relative path (not a submodule). `providers/` namespaces
#   the API-backed commands. Agnostic fleet verbs will live under `fleet/` and be
#   flattened to top level. See ROADMAP.md.

export use providers/gitlab/
export use providers/github/
export use commit.nu

# Agnostic fleet verbs land here in later steps (flattened to top level):
# export use fleet *
