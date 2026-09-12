# The hinge: zoxide entries in, one chosen directory out.
#
# Above this line everything is zoxide (db.nu); below it everything is a host
# doing something with a path (host/). This is the only file that knows both —
# that a candidate is a {score, path} record, and that `choose` wants a record of
# closures describing how such a thing reads.
#
# Nothing chosen comes back as `null`, from here and from `choose` alike. "" is a
# path-shaped answer to "which path?", and a caller that forgets to check gets a
# loud error instead of a quiet `cd ""`.
use ../db.nu
use ../choose
use preview.nu [short dir-preview]

# zoxide entries as {score, path} records, optionally narrowed by query. Records,
# not bare paths: a picker with a preview pane has something to show, and the
# frecency score stays available to whoever renders the row.
def candidates [query?: string] {
  let kw = if ($query | is-empty) { [] } else { [$query] }
  db entries --all ...$kw
}

# How a zoxide entry reads, in the list and in the pane. Both pickers are handed
# the same pair; the one with no pane simply never calls the second.
def looks []: nothing -> record {
  {display: {|| short $in.path }, preview: {|width| dir-preview $width }}
}

# Pick one directory. `null` when nothing was chosen.
export def main [prompt: string, query?: string]: nothing -> any {
  let chosen = (candidates $query | choose ({prompt: $prompt} | merge (looks)))
  if ($chosen == null) { null } else { $chosen.path }
}

# Pick any number of directories. `[]` when nothing was chosen.
export def many [prompt: string, query?: string]: nothing -> list<string> {
  candidates $query
  | choose ({prompt: $prompt, multi: true} | merge (looks))
  | default []
  | get path
}
