# AI-powered content generation helpers.
# Shared by `commit` and the provider `mr` / `pr` commands.

# Generate structured content from a prompt using Claude.
const max_prompt_len = 40_000

export def generate [
  prompt: string   # The full prompt to send
  schema: record   # JSON schema for structured output
  --think          # Use extended thinking (slower, better for complex diffs)
]: nothing -> record {
  print $"(ansi light_cyan)generating content(if $think { ' (extended thinking)' })...(ansi reset)"
  let schema_json = $schema | to json
  let prompt = if ($prompt | str length) > $max_prompt_len {
    print $"(ansi yellow)warning: prompt truncated from ($prompt | str length) to ($max_prompt_len) chars(ansi reset)"
    $"($prompt | str substring 0..$max_prompt_len)\n\n... content truncated ..."
  } else {
    $prompt
  }

  # Fast path (default): --tools "" disables the agent loop and --system-prompt
  # replaces the heavy default Claude Code prompt — cuts latency ~40% by
  # dropping a turn and shedding ~50k cache-read tokens per call.
  # --think restores the default agent/system prompt and bumps effort to max,
  # giving the model room for extended reasoning on tricky diffs.
  let result = if $think {
    ($prompt | claude -p
      --model haiku
      --no-session-persistence
      --effort max
      --output-format json
      --json-schema $schema_json)
  } else {
    ($prompt | claude -p
      --model haiku
      --no-session-persistence
      --tools ""
      --system-prompt "You are a structured-output generator. Output ONLY JSON matching the provided schema. Follow the per-field length and formatting guidance given in the user prompt — keep fields described as 'concise' or 'short' to one line, but allow fields described as multi-paragraph or detailed to use the space they need (including newlines and markdown bullets when appropriate). No commentary outside the JSON."
      --output-format json
      --json-schema $schema_json)
  }
  $result | from json | get structured_output
}

# Interactive review loop: generate, show, let user accept/edit/regenerate/quit.
# Returns null if user quits.
export def review-loop [
  generate_fn: closure       # Closure that returns a record
  user_prompt_pattern: string # Pattern with field placeholders for display
]: nothing -> record {
  mut user_choice = 'n'
  mut result = {}
  while $user_choice != y {
    $result = do $generate_fn
    let user_prompt = $result | format pattern $user_prompt_pattern
    $user_choice = input --numchar 1 --default r $user_prompt
    if $user_choice == q {
      print $"(ansi light_yellow)aborting(ansi reset)"
      return null
    } else if $user_choice == e {
      let t = mktemp --suffix .yaml
      $result | to yaml | save -f $t
      ^$env.EDITOR $t
      $result = open $t -r | from yaml
      $user_choice = 'y'
    }
  }
  $result
}
