# `gg` — implementation roadmap (meta-plan)

`gg` is my **git superset**: it manages whole projects (a GitLab group / GitHub
org as a *fleet* of repos) **and** authors changes to the current repo — under
one roof. Fleet ops use `glab` / `gh`; generated content comes from the
standalone `ai` module.

## Structure (done)

Split by concern into small submodules; generation extracted to a sibling module:

| unit            | commands                           | operates on           | needs            |
|-----------------|------------------------------------|-----------------------|------------------|
| `ai` (sibling)  | `generate`, `review-loop`          | a prompt → text       | Claude           |
| `gg/forge/`     | `gg commit`, `gg mr`, `gg pr`      | the **current** repo  | git, glab/gh, ai |
| `gg/providers/` | `gg gitlab/github list` / `clone`  | a whole **group/org** | git, glab/gh     |
| `gg/fleet/`     | `gg each`, `gg status` (later)     | the **local fleet**   | git              |

`forge`'s commands are flattened to the gg top level (`export use forge *`) and
import `ai` via `use ../../ai`. `ai` stays standalone (not git-specific).

## Philosophy — few powerful functions

Managing a fleet needs a *small* verb set, not a feature zoo. `each` is the
multiplier: most "operations across all repos" are one-liners over it, so they
don't need dedicated commands.

```
gg each { git pull --ff-only }      # update
gg each { git switch main }         # checkout
gg each { git gc }                  # maintenance
gg each { git status -s } | ...     # ad-hoc queries
```

So the whole roadmap is really: **discover → each → status**, plus a couple of
optional conveniences.

---

## Spine (settled)

1. **Split surface.** Provider-agnostic verbs top-level (`gg status`, `gg each`);
   API verbs namespaced (`gg gitlab …` / `gg github …`).
2. **Workspace root.** `lib/root.nu`: `--root` > `$env.gg_root` > cwd. (planted)
3. **Fleet-exec primitive.** One internal "run in every repo, in parallel,
   isolate errors, collect results" helper; `each` / `status` wrap it.
4. **Structured result contract.** `lib/report.nu`: every bulk verb returns a
   `list<record<repo, status, detail>>` table + a colored summary. `par-each`,
   never sequential; one repo's error never aborts the run.
5. **Deep modularization.** Small files, one command per file (`export def main`),
   nested submodules; `lib/` = internal helpers imported by path. (durable pref)

**Verified (nu 0.114):** deep dirs don't leak into the command path; leaf
commands use `export def main`; `export use fleet *` flattens to top level;
`use ../../lib/x.nu` and sibling `use ../ai` both resolve; `lib/` is a plain
folder (no `mod.nu`, not re-exported).

---

## Phase 0 — Foundation

### [x] Structure & module split
Deep one-command-per-file layout; extracted `forge` (authoring) and `ai`
(generation) into their own modules. `gg` is now pure fleet management.

### [ ] Step A — Local repo discovery  *(the only foundation left)*
- **Goal:** enumerate the cloned fleet so `each` / `status` have something to
  iterate.
- **Deliverable:** `lib/discover.nu` → `list<record<name, path, remote, default_branch>>`
  for every cloned repo under the root (`root.nu` feeds it).
- **Decisions to resolve:** walk for `.git` vs. reconcile against the API listing;
  how to handle the nested `path_with_namespace` tree; symlinks / bare repos /
  non-git dirs; pure-local vs. API-backed.
- **Done when:** returns a clean table for a real group tree.

## Phase 1 — The power tools

### [ ] Step B — `gg each`
- **Goal:** run a closure in every repo, in parallel, with a result summary.
- **Deliverable:** the `fleet/` submodule + `lib/report.nu` wired up; `each`
  flattened to top level. Subsumes update / checkout / maintenance as recipes.
- **Decisions to resolve:** parallelism cap; closure signature / per-repo context;
  progress rendering; error policy (collect vs fail-fast).
- **Done when:** `gg each { git pull --ff-only }` updates the fleet and reports
  updated / skipped / failed.

### [ ] Step C — `gg status`
- **Goal:** read-only fleet overview — the command you run most.
- **Deliverable:** one table across all repos: branch, dirty?, ahead/behind, stash?.
- **Decisions to resolve:** columns; ahead/behind with no upstream; `--dirty-only`.
- **Done when:** one glanceable table across the fleet.

## Phase 2 — Optional conveniences (only if wanted)

These are thin wrappers / `each` recipes — build on demand, not upfront.

- **`clone --update` (sync)** — fold update into clone: clone missing + pull existing.
- **`prune`** — report local repos gone from the remote listing; guarded `--remove`.
- **filters** — `--archived` / `--no-forks` / name glob on `list` / `clone`.
- **MR/PR dashboard** — `gg gitlab mrs` / `gg github prs`: open requests across the
  whole group/org (API-only; reuses existing auth).

---

## Critical path

```
structure/split ✓ → A discover → B each → C status
                                     └→ Phase 2 (each-recipes / thin wrappers, optional)
```

Foundation is one step from done (discovery). After that, `each` + `status` are
the whole product; everything else is optional sugar.
