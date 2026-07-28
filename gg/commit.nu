use ai.nu

const commit_prompt_pattern = "Generate a Conventional Commits message from this diff. Produce two fields:
- subject: a one-line summary in the form `type(scope): description`. Under 72 chars, imperative mood, no trailing period. The scope is optional — include it only when a single well-defined area of the codebase is affected.
- body: OMIT IT (empty string) by default. The subject alone is enough for the vast majority of commits — small fixes, refactors, single-purpose changes, anything where the diff is self-explanatory. Only write a body when there is *real context a reviewer cannot infer from the diff*: a non-obvious motivation, a constraint that forced the approach, a deliberate trade-off, a breaking change, or a non-trivial multi-part change that needs to be tied together. When you do write a body, keep it tight — explain the *why*, not the *what*. No file-by-file recaps, no restating the subject in longer form, no padding. If you cannot point to specific context the diff doesn't already convey, leave the body empty.

Recent commits (for tone/style reference):
{log}

Diff:
{diff}"

const commit_schema = {
  type: object
  properties: {
    subject: {type: string}
    body: {type: string}
  }
  required: [subject body]
}

const commit_display_pattern = $"
(ansi cyan_bold)── Commit ─────────────────────────(ansi reset)
(ansi white_bold)  Subject: (ansi reset)(ansi light_yellow){subject}(ansi reset)
(ansi white_bold)  Body:(ansi reset)
(ansi light_yellow){body}(ansi reset)
(ansi cyan_bold)──────────────────────────────────(ansi reset)"

const commit_user_prompt_pattern = $"($commit_display_pattern)
(ansi light_cyan)y: accept - e: edit - r: regenerate - q: quit (ansi reset)"
# Commit staged changes with an optional AI-generated message
export def main [
  --message (-m): string  # Commit message (auto-generated if omitted)
  --yes                   # Do not ask for confirmation
  --think                 # Use extended thinking when generating the message
] {
  let staged = git diff --cached --name-only | str trim
  if ($staged | is-empty) {
    error make --unspanned {msg: "No staged changes to commit"}
  }

  let parts = if ($message != null) {
    {subject: $message, body: ""}
  } else {
    let gen = {||
      let diff = git diff --cached
      let log = git log --oneline -10
      if ($diff | is-empty) {
        error make --unspanned {msg: "No staged changes found"}
      }
      let prompt = {log: $log, diff: $diff} | format pattern $commit_prompt_pattern
      ai generate $prompt $commit_schema --think=$think
    }
    if $yes {
      let result = do $gen
      print ($result | format pattern $commit_display_pattern)
      $result
    } else {
      let result = ai review-loop $gen $commit_user_prompt_pattern
      if ($result == null) { return }
      $result
    }
  }

  if (($parts.body | default "" | str trim) | is-empty) {
    git commit -m $parts.subject
  } else {
    git commit -m $parts.subject -m $parts.body
  }
}
