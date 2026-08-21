# Interactive review loop: generate, show, let user accept/edit/regenerate/quit.
# Returns null if user quits.
export def main [
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
