# Workspace-root resolution for fleet operations.
#
# Every bulk verb (status, update, each, prune, …) operates on the tree of
# cloned repos rooted here. Precedence: explicit --root arg > $env.gg_root > cwd.
#
# NOTE: no consumers yet — planted in Step 1 as the shared convention; first
# exercised by discovery in Step 2 (see ROADMAP.md).
export def main [root?: path]: nothing -> path {
  $root
  | default ($env.gg_root? | default (pwd))
  | path expand
}
