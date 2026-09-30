# gg — fleet manager: a GitLab group / GitHub org as a fleet of repos mirrored
# on disk. Reads the declared desired state in `$env.gg_config` (see README)
# and uses `glab` / `gh` for remote enumeration.
#
# Command surface (config-driven; omit --source to act on every configured source):
#   gg list   [-s source]            — list a source's repos (remote enumeration)
#   gg clone  [-s source]            — clone missing repos into the source's dir
#   gg status [-s source] [--dirty]  — branch / ahead-behind / dirty / stash per repo
#   gg each   [-s source] {closure}  — run a closure in every repo, in parallel
#   gg sync   [-s source] [--force] [--dry-run] — reconcile remote/disk drift
#
# AI-assisted authoring (commit / mr / pr) is NOT here any more: it lives in
# ~/.config/nushell/scripts/ai-git.nu as ai-commit / ai-mr / ai-pr.
#
# Layout
#   One command per file (`export def main`). `fleet/` = fleet verbs (flattened).
#   `providers/` + `lib/` = internal helpers imported by relative path (not
#   re-exported). See ROADMAP.md.

export use fleet *
