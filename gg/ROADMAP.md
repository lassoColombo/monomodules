# `gg` — implementation roadmap (meta-plan)

`gg` is my **git superset**: it manages whole projects (a GitLab group / GitHub
org as a *fleet* of repos) **and** authors changes to the current repo — under
one roof. Fleet ops use `glab` / `gh`; generated content comes from the
standalone `ai` module.

## Structure (done)

Split by concern; the fleet is **config-driven** — `$env.gg_config` declares each
source (provider, host, group/org, local `dir`; see README).

| unit            | commands                                     | operates on          | needs        |
|-----------------|----------------------------------------------|----------------------|--------------|
| `ai` (sibling)  | `generate`, `review-loop`                    | a prompt → text      | Claude       |
| `gg/forge/`     | `gg commit`, `gg mr`, `gg pr`                | the **current** repo | git, glab/gh, ai |
| `gg/fleet/`     | `gg list`, `gg clone` (`status`/`each` next) | the **fleet**        | git, glab/gh |
| `gg/providers/` | *(internal)* `enumerate` adapters            | one source's remote  | glab / gh    |
| `gg/lib/`       | *(internal)* `config`, `discover`, `report`  | config + local repos | git          |

`forge` and `fleet` commands are flattened to the gg top level (`export use … *`);
`forge` imports the standalone `ai` via `use ../../ai`. `providers/` and `lib/`
are internal (imported by path, not re-exported). **Only `enumerate` is
provider-specific** — clone / discover / status / each are pure git.

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

1. **Unified, config-driven surface.** Fleet verbs (`gg list` / `clone` /
   `status` / `each`) take a source handle from `$env.gg_config` — no provider
   namespaces. Provider differences live only in internal `enumerate` adapters.
2. **Declared desired state.** `$env.gg_config` (record keyed by handle) is the
   source of truth — provider / host / group|org / local `dir`. `lib/config.nu`
   reads + normalizes + resolves it (kube-bridge-style). Supersedes the
   single-root idea (`root.nu` removed).
3. **Fleet-exec primitive.** One internal "run in every repo, in parallel,
   isolate errors, collect results" helper; `each` / `status` wrap it.
4. **Structured result contract.** `lib/report.nu`: every bulk verb returns a
   `list<record<repo, status, detail>>` table + a colored summary. `par-each`,
   never sequential; one repo's error never aborts the run.
5. **Deep modularization.** Small files, one command per file (`export def main`),
   nested submodules; `lib/` = internal helpers imported by path. (durable pref)

**Verified (nu 0.114):** deep dirs don't leak into the command path; leaf
commands use `export def main`; `export use … *` flattens to top level;
`use ../../lib/x.nu` and sibling `use ../ai` both resolve; `lib/` is a plain
folder (no `mod.nu`, not re-exported). Config resolve, provider dispatch, and
`discover` verified against a throwaway fleet.

---

## Phase 0 — Foundation

### [x] Structure & module split
Deep one-command-per-file layout; extracted `forge` (authoring) and `ai`
(generation) into their own modules. `gg` is now pure fleet management.

### [x] Step A — Local repo discovery  *(done)* + config-driven interface
- **Shipped `lib/discover.nu`:** walks each configured source's `dir` for `.git`,
  returns `{source, provider, name, path, remote, default_branch}` — pure-local,
  no API; provider comes from config, missing dirs skip.
- **Shipped the config-driven interface it rides on:** `lib/config.nu`
  (resolve/normalize `$env.gg_config`), `providers/{gitlab,github}.nu` `enumerate`
  adapters + `providers/mod.nu` dispatch, and unified `gg list` / `gg clone`.
- **Internal for now:** `discover` isn't a command yet — it feeds `status`/`each`
  (Steps B/C), which will surface the fleet.

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
- **MR/PR dashboard** — `gg mrs` / `gg prs`: open requests across a source
  (API-only; reuses existing auth).

---

## Critical path

```
structure/split ✓ → A discover → B each → C status
                                     └→ Phase 2 (each-recipes / thin wrappers, optional)
```

Foundation is one step from done (discovery). After that, `each` + `status` are
the whole product; everything else is optional sugar.
