# `gg` — implementation roadmap (meta-plan)

`gg` manages **whole projects** (a GitLab group / GitHub org = a fleet of repos),
not individual repositories. It uses `glab` / `gh` to list & clone, and plain
`git` to operate on the local fleet.

This is a **meta-plan**: a sequence of self-contained steps. Each step is its own
mini-project run in its own session as:

> **explore** the current code & tools → **plan** the step → **ask** the open
> decisions below → **execute** → **verify** on a real group/org.

Do not batch steps. Finish and verify one before starting the next. Tick the box
when a step lands.

---

## Current surface (starting point)

- `gg gitlab list-repos <group>` / `gg github list-repos <org>` — names only
- `gg gitlab clone-group <group>` / `gg github clone-org <org>` — sequential, skips existing
- `gg gitlab merge-request` / `gg github pull-request` — per-repo, AI-generated
- `gg commit` — per-repo, AI-generated
- internal: `merge-request.nu` (`generate-mr-content`), `ai.nu` (`generate`, `review-loop`)

**Gap:** of the list / clone / **update** trio, update is entirely absent, and
there is no way to *see* or *act on* the fleet as a whole.

---

## Architectural spine (decided in Step 1, relied on by everything after)

These decisions ripple through every later step — settle them first.

1. **Provider-agnostic local verbs vs. provider-namespaced.** Local-git ops
   (`update`, `status`, `each`, `checkout`) don't care about GitLab vs GitHub —
   they operate on cloned repos. API-backed ops (`list`, `clone`, `mrs`/`prs`,
   filters) do. *Recommendation:* top-level agnostic verbs for the git ops,
   keep `gg gitlab …` / `gg github …` for the API ones.
2. **Workspace root.** One convention for "where the fleet lives": a `--root`
   flag defaulting to cwd or `$env.gg_root` (mirrors kube-bridge's
   `$env.kubebridge_config`).
3. **One fleet-exec primitive.** A single internal "run this in every repo,
   in parallel, isolate errors, collect results" helper. `status`, `update`,
   `each`, `checkout`, `prune` are all thin wrappers over it.
4. **Structured result contract.** Every bulk verb returns a table + prints a
   colored summary (matching the commit/MR display style). `par-each`, never
   sequential `each`; never let a single repo's git error abort the run.
5. **Deep modularization.** Small files, **one command per file**
   (`export def main`), grouped into nested submodules; `lib/` holds internal
   helpers imported by relative path. Filesystem depth need not equal
   command-path depth. (Durable preference — applies to all future work.)

### Decisions locked (Step 1)

- **Surface:** *split* — agnostic git verbs top-level (`gg status/update/each/commit`),
  API verbs namespaced (`gg gitlab …` / `gg github …`).
- **Layout:** *deep, one command per file* (`lib/` + `providers/` + `fleet/`).
- **Renames (breaking, no aliases — module is one commit old):**
  `list-repos`→`list`, `clone-group`/`clone-org`→`clone`,
  `merge-request`→`mr`, `pull-request`→`pr`.
- **Verified (nu 0.114):** deep dirs don't leak into the command path; leaf
  commands use `export def main`; `export use fleet *` flattens to top level;
  `use ../../lib/x.nu` resolves; `lib/` is a plain folder (no `mod.nu`, not
  re-exported).

---

## PHASE 0 — Foundation (gates everything)

### [x] Step 1 — Command architecture & module layout  *(DONE — module loads, surface verified)*
- **Goal:** restructure into the deep modular layout + split surface; move shared
  internals; plant the root & report conventions. No new user-facing behavior.
- **Depends on:** —

**Target tree**
```
gg/
  mod.nu                doc header + re-exports
  commit.nu             gg commit            (agnostic, cwd repo)
  lib/                  internal, imported by path (no mod.nu, not re-exported)
    ai.nu               (moved) generate, review-loop
    mr-content.nu       (moved) generate-mr-content
    root.nu             workspace root: --root > $env.gg_root > pwd
    report.nu           result contract + colored summary (provisional)
  providers/
    gitlab/
      mod.nu            export use list / clone / mr
      fetch.nu          internal: paginated group projects (NOT exported)
      list.nu           gg gitlab list  <group>
      clone.nu          gg gitlab clone <group>
      mr.nu             gg gitlab mr    <src> <tgt>
    github/
      mod.nu            export use list / clone / pr
      fetch.nu          internal: org repos (NOT exported)
      list.nu           gg github list  <org>
      clone.nu          gg github clone <org>
      pr.nu             gg github pr    <src> <tgt>
  fleet/                (Steps 3–5, 9) agnostic verbs, flattened to top level
```

**Tasks**
1. Create `lib/`; move `ai.nu`→`lib/ai.nu`, `merge-request.nu`→`lib/mr-content.nu`.
2. Add `lib/root.nu` (working) and `lib/report.nu` (provisional contract + summary).
3. Split `gitlab.nu` → `providers/gitlab/{mod,fetch,list,clone,mr}.nu`.
4. Split `github.nu` → `providers/github/{mod,fetch,list,clone,pr}.nu`.
5. Rewire imports: providers `use ../../lib/mr-content.nu`; `commit.nu` → `use lib/ai.nu`.
6. Rewrite `mod.nu`: doc header + `export use providers/gitlab/`, `providers/github/`,
   `commit.nu` (+ commented `fleet` flatten placeholder for later steps).
7. Delete old `gitlab.nu`, `github.nu`, `merge-request.nu`, `ai.nu`.
8. Verify: `use ./gg` loads clean; `scope commands` matches the target surface.

- **Out of scope (next steps):** `lib/discover.nu` (Step 2), the `fleet` exec
  primitive + `gg each` (Step 3), all agnostic verbs (Steps 4+).
- **Done when:** module loads, `scope commands` matches the target surface, and
  the four existing commands still run under their new names.

### [ ] Step 2 — Workspace root + local repo discovery
- **Goal:** know where the fleet lives and enumerate cloned repos.
- **Depends on:** Step 1
- **Scope:** the `--root` / `$env.gg_root` convention; an internal
  `discover-repos` that finds cloned repos (walk for `.git`, and/or reconcile
  against the API listing) → `{name, path, remote, default_branch, …}`.
- **Decisions to resolve:** env var name? walk depth & how to handle the nested
  `path_with_namespace` tree? symlinks / bare repos / non-git dirs? does
  discovery hit the API or stay pure-local?
- **Done when:** `discover-repos` returns a clean table for a real group tree.

### [ ] Step 3 — Fleet-exec primitive + reporting
- **Goal:** the backbone every bulk verb reuses.
- **Depends on:** Step 2
- **Scope:** internal `for-each-repo` (par-each, capture exit/stdout/stderr,
  per-repo error isolation) + a standard result table & summary renderer. The
  public `gg each` / `exec` is the exported thin wrapper (takes a closure).
- **Decisions to resolve:** parallelism default & cap? progress rendering for
  long runs? error policy (collect vs fail-fast)? closure signature / what
  context each repo gets? summary format.
- **Done when:** `gg each { git rev-parse --abbrev-ref HEAD }` returns a table
  across the fleet.

---

## PHASE 1 — Core fleet verbs

### [ ] Step 4 — `status`
- **Goal:** read-only fleet overview; the safe first consumer of the primitive.
- **Depends on:** Steps 2–3
- **Scope:** per repo → branch, dirty?, ahead/behind upstream, stash?, maybe
  last commit. Parse `git status --porcelain=2 --branch`.
- **Decisions to resolve:** columns? ahead/behind when no upstream? sort /
  grouping? `--dirty-only` and similar filters? color thresholds.
- **Done when:** one glanceable table across all repos.

### [ ] Step 5 — `update` / `pull`  ← the headline feature
- **Goal:** bring the fleet current, safely and idempotently.
- **Depends on:** Steps 2–4 (reuses status logic to judge safety)
- **Scope:** per repo fetch + fast-forward the default branch; detect default
  branch (`origin/HEAD`); skip or autostash dirty trees; fetch-only when a repo
  isn't on its default branch; parallel; summary
  (updated / up-to-date / skipped / failed).
- **Decisions to resolve:** default-branch detection strategy? dirty policy
  (skip vs autostash vs flag)? off-default policy? ff-only vs rebase vs merge?
  uncloned repos → delegate to clone/sync? network-fail retries?
- **Done when:** clear report; **never clobbers local work.**

---

## PHASE 2 — Sync & hygiene

### [ ] Step 6 — `clone` / `sync` refactor
- **Goal:** fold clone onto the foundation; make it a true sync.
- **Depends on:** Steps 2, 3, 5
- **Scope:** refactor `clone-*` onto discovery + reporting + par-each; add
  `sync` = clone-missing + update-existing; report new / updated / removed.
- **Decisions to resolve:** separate `clone` vs `sync`, or one command with
  `--update`? parallel-clone safety? shallow/partial clone options? dirs that
  exist but aren't git repos?
- **Done when:** one command reconciles the remote listing → local tree.

### [ ] Step 7 — Filters & scoping
- **Goal:** control which repos list/clone/sync touch.
- **Depends on:** Steps 1, 6
- **Scope:** `--archived`, `--no-forks`, `--visibility`, name glob/regex —
  applied consistently to list/clone/sync/fetch on **both** providers.
- **Decisions to resolve:** which filters map cleanly to both `glab api` & `gh`?
  server-side vs client-side? default to excluding archived? glob syntax.
- **Done when:** symmetric filter flags across providers.

### [ ] Step 8 — `prune` / drift detection
- **Goal:** detect & reconcile local-vs-remote divergence.
- **Depends on:** Steps 2, 6
- **Scope:** report local repos missing from the remote listing
  (archived/deleted/renamed) and remote repos not yet cloned; `--remove` to
  delete orphans (guarded).
- **Decisions to resolve:** renamed vs deleted? safety on `--remove` (confirm;
  refuse if dirty or has unpushed commits)? dry-run by default? local-only work.
- **Done when:** clear drift report + guarded cleanup.

---

## PHASE 3 — Cross-repo actions & dashboards

### [ ] Step 9 — `checkout` / `switch` across the fleet
- **Goal:** put the whole fleet on a branch (e.g. back to `main`).
- **Depends on:** Step 3
- **Scope:** checkout a given branch in each repo, skip where absent, report;
  optional create-if-missing.
- **Decisions to resolve:** skip vs create when branch absent? refuse on dirty?
  track the remote branch? a "restore to default" helper?
- **Done when:** bulk checkout with safe skips.

### [ ] Step 10 — Fleet MR/PR (& issue) dashboard
- **Goal:** cross-project visibility into open MRs/PRs. Reuses existing auth.
- **Depends on:** Step 1
- **Scope:** `gg gitlab mrs <group>` via `glab api …/merge_requests`;
  `gg github prs <org>` via `gh search prs`; unified table (repo, title, author,
  age, url, draft?, reviewers).
- **Decisions to resolve:** fields? open-only or a states flag? pagination?
  author/assignee filters? one `gg mrs` dispatching by provider?
- **Done when:** one table of everything awaiting attention across the fleet.

---

## PHASE 4 — Polish

### [ ] Step 11 — Docs, consistency, tests
- **Goal:** finish it.
- **Depends on:** all
- **Scope:** mod.nu/README doc surface (house style + the
  readme-commands-section-generator / `override` command); consistency pass
  (flags, colors, error messages); nutest coverage where feasible (discovery,
  status/porcelain parsing, filters are pure enough to test; git/network via
  fixtures or skipped); completers (branch / group / root).
- **Decisions to resolve:** how much to test given side effects? regenerate
  README via the existing generator?
- **Done when:** documented, consistent, testable core covered.

---

## Critical path & parallelism

```
1 → 2 → 3 → 4 → 5 → 6 → 7
                 └→ 8 (after 6)
        3 ──────→ 9
        1 ──────→ 10
                       everything → 11
```

- **Foundation (1→2→3) is strictly sequential** and blocks the rest.
- After Step 3: **Step 9** (checkout) and **Step 10** (dashboard) are independent
  and can jump the queue if wanted.
- **Steps 4→5→6** are the recommended main line (status proves the primitive,
  update reuses status, sync reuses update).
- **Step 11** is continuous — fold docs/tests in as each verb lands rather than
  saving it all for the end.
