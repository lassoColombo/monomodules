# Drift reconciliation logic + apply primitives for `gg sync`.
# Pure/testable: no prompts here. The interactive orchestration lives in
# fleet/sync.nu.
use gitstate.nu repo-status

# Normalize a git remote url to a comparable key: host/path, lowercased, with
# scheme / user@ / trailing .git stripped — so ssh and https forms of the same
# repo compare equal.
export def norm-url []: string -> string {
  $in
  | str trim
  | str replace -r '^\w+://' ''
  | str replace -r '^[^@/]+@' ''
  | str replace -r '\.git$' ''
  | str replace ':' '/'
  | str lowercase
}

# Classify one on-disk repo against a remote index (rows of {url, source, correct, dir}).
# Match is by remote URL. Returns { cat, target_source, target_dir, correct } where
# cat ∈ aligned | misplaced | wrong-source | orphan.
export def classify [repo: record, index: table]: nothing -> record {
  let hit = ($index | where url == ($repo.remote | norm-url) | get 0?)
  if ($hit == null) {
    { cat: "orphan", target_source: null, target_dir: null, correct: null }
  } else if ($hit.source != $repo.source) {
    { cat: "wrong-source", target_source: $hit.source, target_dir: $hit.dir, correct: $hit.correct }
  } else if ($hit.correct != $repo.name) {
    { cat: "misplaced", target_source: $hit.source, target_dir: $hit.dir, correct: $hit.correct }
  } else {
    { cat: "aligned", target_source: $hit.source, target_dir: $hit.dir, correct: $hit.correct }
  }
}

# Move a repo dir (a non-destructive rename — all git state travels with it).
# Skips if the target is occupied.
export def act-move [from: path, to: path]: nothing -> record {
  if ($to | path exists) { return { ok: false, msg: $"target exists: ($to)" } }
  mkdir ($to | path dirname)
  mv $from $to
  { ok: true, msg: $"moved → ($to)" }
}

# Move a repo into <source dir>/.gg-trash/<rel> — never `rm`. Refuses if the repo
# has unsaved work (dirty tree, unpushed commits, or stashes). `.gg-trash` is a
# dotdir, so `discover` already ignores it (trashed repos won't reappear).
export def act-trash [repo: path, source_dir: path, rel: string]: nothing -> record {
  let s = (repo-status $repo)
  if ($s.dirty > 0 or $s.ahead > 0 or $s.stash > 0) {
    return { ok: false, msg: "refused: unsaved work (dirty / unpushed / stash)" }
  }
  let dest = ($source_dir | path join ".gg-trash" $rel)
  if ($dest | path exists) { return { ok: false, msg: $"trash target exists: ($dest)" } }
  mkdir ($dest | path dirname)
  mv $repo $dest
  { ok: true, msg: $"trashed → .gg-trash/($rel)" }
}

# Clone a repo to an absolute path. Skips if the target is occupied.
export def act-clone [url: string, to: path]: nothing -> record {
  if ($to | path exists) { return { ok: false, msg: $"target exists: ($to)" } }
  mkdir ($to | path dirname)
  git clone $url $to
  { ok: true, msg: $"cloned → ($to)" }
}
