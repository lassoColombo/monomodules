# The picker with no pane, so `opts.preview` is never called and pick/preview.nu
# never runs. The whole terminal is the list, which is why nothing trims a row
# here.
#
# The prompt gets zz's own accents — ANSI names, so the colours come from the
# terminal's palette (yellow → star yellow, blue → sky-swirl blue) and the
# palette stays the single source of truth.
export def pick [opts: record] {
  let items = $in
  let prompt = $"(ansi yellow_bold)▸(ansi reset) (ansi blue_bold)($opts.prompt)(ansi reset)"
  if ($opts.multi? | default false) {
    $items | input list --fuzzy --multi --display $opts.display $prompt
  } else {
    $items | input list --fuzzy --display $opts.display $prompt
  }
}
