use ai.nu

const mr_prompt_pattern = "Generate a merge request title and description from this diff.
- title: a synthetic one-line summary. Under 72 chars, imperative mood, no trailing period. It should read like a good commit subject — what a reviewer sees in a list of MRs and immediately understands.
- description: a descriptive explanation aimed at a reviewer. Cover *what* changed (grouped by area or theme, not file by file), *why* it changed (motivation, context, any issue or ticket referenced in the commits), and any implementation detail, trade-off, or follow-up worth flagging. Use short paragraphs separated by blank lines, and a bulleted list when enumerating several distinct points. Be substantive but not padded — match the depth to the size of the change.

Commits:
{log}

Diff:
{diff}"

const mr_schema = {
  type: object
  properties: {
    title: {type: string}
    description: {type: string}
  }
  required: [title description]
}

const mr_display_pattern = $"
(ansi cyan_bold)── Merge Request ──────────────────(ansi reset)
(ansi white_bold)  Title:       (ansi reset)(ansi light_yellow){title}(ansi reset)
(ansi white_bold)  Description: (ansi reset)(ansi light_yellow){description}(ansi reset)
(ansi cyan_bold)──────────────────────────────────(ansi reset)"

const mr_user_prompt_pattern = $"($mr_display_pattern)
(ansi light_cyan)y: accept - e: edit - r: regenerate - q: quit (ansi reset)"

# Generate merge request / pull request content from a diff between two branches.
# Returns {title: string, description: string} or null if the user quits.
export def generate-mr-content [
  source_branch: string
  target_branch: string
  --title (-t): string
  --description (-d): string
  --yes
  --think  # Use extended thinking when generating the content
]: nothing -> record {
  if ($title != null and $description != null) {
    return {title: ($title | default ""), description: ($description | default "")}
  }
  let gen = {||
    let diff = git diff $"($target_branch)...($source_branch)"
    let log = git log --oneline $"($target_branch)..($source_branch)"
    if ($diff | is-empty) {
      error make --unspanned {msg: $"No diff found between ($target_branch) and ($source_branch)"}
    }
    let prompt = {log: $log, diff: $diff} | format pattern $mr_prompt_pattern
    ai generate $prompt $mr_schema --think=$think
  }
  if $yes {
    let result = do $gen
    print ($result | format pattern $mr_display_pattern)
    $result
  } else {
    let result = ai review-loop $gen $mr_user_prompt_pattern
    if ($result == null) { return null }
    $result
  }
}
