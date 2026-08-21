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
| `url` | no | reserved (reference / open in browser) |

## Commands

Fleet — omit `[source]` to act on **every** configured source:

- `gg list [source]` — list a source's repos (remote enumeration; no disk writes)
- `gg clone [source]` — clone missing repos into the source's `dir` (idempotent)

Authoring — current repo:

- `gg commit` — commit staged changes with an AI-generated message
- `gg mr <src> <tgt>` — open a GitLab merge request (AI description)
- `gg pr <src> <tgt>` — open a GitHub pull request (AI description)

See `ROADMAP.md` for what's planned (`status`, `each`).
