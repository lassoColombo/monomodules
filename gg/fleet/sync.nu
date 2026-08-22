use ../lib/config.nu
use ../lib/discover.nu
use ../lib/gitstate.nu repo-status
use ../lib/reconcile.nu [norm-url classify force-action act-move act-trash act-clone]
use ../providers

def source-completer [] { $env.gg_config? | default {} | columns }
def styled [t: string]: nothing -> string { $"(ansi yellow_bold)▸(ansi reset) (ansi blue_bold)($t)(ansi reset)" }

# Compact one-line git state for a diagnosis line.
def fmt-state [s: record]: nothing -> string {
  if ($s.dirty == 0 and $s.ahead == 0 and $s.behind == 0 and $s.stash == 0) {
    $"(ansi green)clean(ansi reset)"
  } else {
    ([
      (if $s.dirty  > 0 { $"(ansi yellow)($s.dirty) dirty(ansi reset)" })
      (if $s.ahead  > 0 { $"(ansi green)($s.ahead)↑(ansi reset)" })
      (if $s.behind > 0 { $"(ansi red)($s.behind)↓(ansi reset)" })
      (if $s.stash  > 0 { $"($s.stash) stash" })
    ] | compact | str join " · ")
  }
}

# Build a plan entry for applying `action` to `repo` — shared by the interactive
# picker and the forced defaults. Returns null for "skip" (nothing to do).
def plan-entry [repo: record, action: string, src_of: record]: nothing -> any {
  match $action {
    "move"  => ({ action: "move",  desc: $"[($repo.source)] ($repo.name) → ($repo.correct)", from: $repo.path, to: ($repo.target_dir | path join $repo.correct) })
    "trash" => ({ action: "trash", desc: $"[($repo.source)] ($repo.name)", repo: $repo.path, source_dir: ($src_of | get $repo.source | get dir), rel: $repo.name })
    "clone" => ({ action: "clone", desc: $"[($repo.source)] ($repo.name)", url: $repo.remote, to: ($repo.target_dir | path join $repo.correct) })
    _ => null
  }
}

# Reconcile drift between the configured remotes and what's on disk. Diagnoses each
# repo (misplaced / wrong-source / orphan / missing).
#
# Interactive by default: walk repo-by-repo, you choose per repo, then confirm the
# collected plan once before it applies. With --force: no prompts — apply each
# source's configured sensible default per case (see `sync` in gg_config, e.g.
# `personal: { sync: { misplaced: skip } }`); defaults are move/move/skip/clone.
#
# Moves are non-destructive; deletes go to <dir>/.gg-trash and are refused if the
# repo has unsaved work. Acts on the whole fleet by default; --source limits to one.
# --dry-run prints the drift and stops (with --force, adds the action it *would* take).
export def main [
  --source (-s): string@source-completer
  --force        # skip all prompts; apply each source's configured default per case
  --dry-run
]: nothing -> any {
  let all_sources = (config resolve)
  let src_of = ($all_sources | reduce --fold {} {|s, acc| $acc | insert $s.name $s })

  let scope = (if ($source | is-empty) { $all_sources } else { config resolve $source })
  let scope_names = ($scope | get name)

  # wrong-source drift can only occur between sources on the same host, so limit
  # the cross-reference index (and the network hit) to same-host sources — a
  # personal (github) audit never touches the gitlab host, and vice-versa.
  let scope_hosts = ($scope | get host | uniq)
  let index_sources = ($all_sources | where host in $scope_hosts)
  print -e $"(ansi light_cyan)sync: enumerating (($index_sources | length)) source\(s\) on (($scope_hosts | str join ', ')) …(ansi reset)"
  let index = ($index_sources | each {|src|
    providers enumerate $src | each {|r| { url: ($r.ssh_url | norm-url), source: $src.name, correct: $r.path, ssh_url: $r.ssh_url, dir: $src.dir } }
  } | flatten)

  let disk = ($scope | each {|src|
    discover $src.name | each {|r| $r | merge (classify $r $index) }
  } | flatten)

  let disk_keys = ($disk | each {|d| $d.remote | norm-url })
  let missing = ($index | where source in $scope_names | where url not-in $disk_keys | each {|e|
    { source: $e.source, name: $e.correct, path: null, remote: $e.ssh_url, cat: "missing", target_source: $e.source, target_dir: $e.dir, correct: $e.correct }
  })

  let flagged = (($disk | where cat != "aligned") ++ $missing)
  let n_aligned = ($disk | where cat == "aligned" | length)
  print -e $"(ansi green)($n_aligned) aligned(ansi reset) · (ansi yellow_bold)($flagged | length) to review(ansi reset)"

  if ($flagged | is-empty) {
    print $"(ansi green_bold)✓ fleet reconciled — no drift(ansi reset)"
    return
  }
  if $dry_run {
    if $force {
      return ($flagged | insert would {|r| force-action $r.cat ($src_of | get $r.source) } | select source name cat correct would)
    }
    return ($flagged | select source name cat correct)
  }

  mut plan = []
  if $force {
    # no prompts — apply each source's configured sensible default per case.
    for repo in $flagged {
      let entry = (plan-entry $repo (force-action $repo.cat ($src_of | get $repo.source)) $src_of)
      if $entry != null { $plan = ($plan | append $entry) }
    }
    print -e $"(ansi light_cyan)force: (($plan | length)) action\(s\), (($flagged | length) - ($plan | length)) skipped by policy(ansi reset)"
  } else {
    # interactive — diagnose each repo and let you choose.
    mut aborted = false
    for repo in $flagged {
      if $aborted { break }
      let icon = ({ misplaced: "🔧", "wrong-source": "📦", orphan: "👻", missing: "⬇️" } | get -o $repo.cat | default "•")
      print ""
      print $"($icon) (ansi light_purple)[($repo.source)](ansi reset) (ansi white_bold)($repo.name)(ansi reset)"
      if $repo.cat == "misplaced"    { print $"   misplaced — should sit at (ansi green)($repo.correct)(ansi reset)" }
      if $repo.cat == "wrong-source" { print $"   belongs to (ansi green)($repo.target_source)(ansi reset) at (ansi green)($repo.correct)(ansi reset)" }
      if $repo.cat == "orphan"       { print $"   (ansi yellow)no matching upstream in your configured sources(ansi reset)" }
      if $repo.cat == "missing"      { print $"   (ansi cyan)in the remote listing, not on disk(ansi reset)" }
      if ($repo.path != null) { print $"   (fmt-state (repo-status $repo.path))" }

      let opts = (if $repo.cat in ["misplaced" "wrong-source"] {
          [ $"move → ($repo.correct)" "trash" "skip" "quit" ]
        } else if $repo.cat == "orphan" {
          [ "trash" "skip" "quit" ]
        } else {
          [ "clone" "skip" "quit" ]
        })
      let pick = ($opts | input list (styled "action"))

      if ($pick | is-empty) or ($pick == "quit") { $aborted = true; continue }
      if $pick == "skip" { continue }
      let action = (if ($pick | str starts-with "move") { "move" } else { $pick })
      let entry = (plan-entry $repo $action $src_of)
      if $entry != null { $plan = ($plan | append $entry) }
    }
  }

  if ($plan | is-empty) {
    print $"\n(ansi yellow)nothing to do — no changes made(ansi reset)"
    return
  }

  print $"\n(ansi cyan_bold)── plan ────────────────────(ansi reset)"
  $plan | group-by action | items {|a, its| print $"  (ansi white_bold)($a)(ansi reset): ($its | length)" }
  print ""
  $plan | each {|p| print $"   ($p.action)  ($p.desc)" }
  if not $force {
    let go = (["no — abort" "yes — apply"] | input list (styled "apply this plan?"))
    if ($go != "yes — apply") {
      print $"(ansi yellow)aborted — no changes made(ansi reset)"
      return
    }
  }

  print ""
  for p in $plan {
    let res = (if $p.action == "move" {
        act-move $p.from $p.to
      } else if $p.action == "trash" {
        act-trash $p.repo $p.source_dir $p.rel
      } else {
        act-clone $p.url $p.to
      })
    let mark = (if $res.ok { $"(ansi green)✓(ansi reset)" } else { $"(ansi red)✗(ansi reset)" })
    print $"  ($mark) ($p.desc) — ($res.msg)"
  }
}
