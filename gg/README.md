# gg

My **git superset**: manage whole projects (a GitLab group / GitHub org as a
*fleet* of repos) and author changes to the current repo, under one roof.

Fleet commands are **config-driven** — they read the desired state from
`$env.gg_config`. Authoring commands (`commit` / `mr` / `pr`) act on the current
repo and need no config. Content generation comes from the sibling `ai` module.

## Configuration

`$env.gg_config` is a record keyed by a **source handle** (the name you type).
Each entry declares one group/org to mirror locally:

```nu
$env.gg_config = {
  elmec: {
    provider: gitlab
    host:  "git.elmec.com"   # optional; defaults per provider
    group: "platform"         # group path ("a/b") or numeric id
    dir:   "~/work/elmec"     # where this source lives on disk
  }
  personal: {
    provider: github
    org:  "lasso"
    dir:  "~/projects/personal"
    # optional: what `gg sync --force` does per drift case for this source.
    # here — a hand-organized layout — never move; only clone what's missing.
    sync: { misplaced: skip, wrong-source: skip, orphan: skip }
  }
}
```

| field | required | meaning |
|---|---|---|
| `provider` | yes | `gitlab` or `github` |
| `dir` | yes | local directory; repos mirror the provider tree beneath it |
| `group` | gitlab | group path (`a/b`) or numeric id |
| `group_id` | gitlab (alt) | numeric id; takes precedence over `group` |
| `org` | github | organization (or user) login |
| `host` | no | API host; defaults `git.elmec.com` (gitlab) / `github.com` (github) |
| `sync` | no | per-case `gg sync --force` policy (see below); overrides the defaults |
| `url` | no | reserved (reference / open in browser) |

### `gg sync --force` policy

`gg sync` is interactive by default. With `--force` it skips every prompt and
applies one sensible default action per drift case. A source's `sync` record
overrides those defaults per case (unset cases fall through to the default).

| case | meaning | actions | default |
|---|---|---|---|
| `misplaced` | right source, wrong path | move / trash / skip | `move` |
| `wrong-source` | belongs to another source | move / trash / skip | `move` |
| `orphan` | no matching configured upstream | trash / skip | `skip` |
| `missing` | in the remote listing, not on disk | clone / skip | `clone` |

`move` is a non-destructive rename; `trash` relocates to `<dir>/.gg-trash` and is
**refused if the repo has unsaved work**; `clone` fetches it. Preview exactly what
`--force` would do with `gg sync --dry-run --force` (adds a `would` column).

## Commands

Fleet — act on **every** configured source by default; `--source`/`-s <handle>`
scopes to one:

- `gg list [-s src]` — list a source's repos (remote enumeration; no disk writes)
- `gg clone [-s src]` — clone missing repos into the source's `dir` (idempotent)
- `gg status [-s src] [--dirty]` — branch / ahead-behind / dirty / stash, per repo
- `gg each [-s src] {closure}` — run a closure in every repo, in parallel
- `gg sync [-s src] [--force] [--dry-run]` — reconcile drift between remotes and
  disk (interactive; `--force` applies the configured per-source defaults)

Authoring — current repo:

- `gg commit` — commit staged changes with an AI-generated message
- `gg mr <src> <tgt>` — open a GitLab merge request (AI description)
- `gg pr <src> <tgt>` — open a GitHub pull request (AI description)

See `ROADMAP.md` for optional Phase 2 conveniences.
