# Interactively inspect complex data structures with a fuzzy picker.
#
# Drill into records, tables, and lists with fuzzy search.
# Enter drills into the selected item. Esc returns the current value.
# Primitive values are returned immediately.
#
# Record: fuzzy-find over keys, preview shows the value.
# Table: prompts for a display column, fuzzy-find over rows, preview shows the row.
# List: fuzzy-find over items directly.
#
# The previews are the whole point of this module, and they are the one thing
# Nushell's built-in picker cannot draw — so telescope still WORKS on the default
# picker (you drill in blind, by key or by column value) and comes alive on one
# that has a preview pane. Which picker it gets is the SK switch at the top of
# picker.nu; what a value looks like in the pane is preview.nu's.
#
# This file is the drilling itself: what there is to choose from at each step,
# and what each row reads as.
use picker.nu choose
use preview.nu preview-of

# Recursively search a data structure for a pattern in keys or primitive values
def search-recurse [pattern: string, path: string]: any -> table<path: string, value: any> {
  let data = $in
  let type = ($data | describe)

  if ($type | str starts-with "record") {
    $data | transpose key value | each {|pair|
      let p = if ($path | is-empty) { $pair.key } else { $"($path).($pair.key)" }
      let vtype = ($pair.value | describe)
      let is_prim = ($vtype in ["string" "int" "float" "bool" "duration" "filesize" "date"])
      let key_hit = (($pair.key | into string) =~ $pattern)
      let val_hit = if $is_prim { ($pair.value | into string) =~ $pattern } else { false }
      let hits = if ($key_hit or $val_hit) { [{path: $p, value: $pair.value}] } else { [] }
      let children = if (not $is_prim) { $pair.value | search-recurse $pattern $p } else { [] }
      $hits | append $children
    } | flatten
  } else if ($type | str starts-with "table") {
    $data | enumerate | each {|entry|
      let p = $"($path)[($entry.index)]"
      let row = $entry.item
      let row_hit = ($row | transpose key value | any {|pair|
        let vt = ($pair.value | describe)
        let is_prim = ($vt in ["string" "int" "float" "bool" "duration" "filesize" "date"])
        (($pair.key | into string) =~ $pattern) or (if $is_prim { ($pair.value | into string) =~ $pattern } else { false })
      })
      let hits = if $row_hit { [{path: $p, value: $row}] } else { [] }
      let children = ($row | search-recurse $pattern $p)
      $hits | append $children
    } | flatten
  } else if ($type | str starts-with "list") {
    $data | enumerate | each {|entry|
      let p = $"($path)[($entry.index)]"
      let item = $entry.item
      let itype = ($item | describe)
      let is_prim = ($itype in ["string" "int" "float" "bool" "duration" "filesize" "datetime"])
      let hit = if $is_prim { ($item | into string) =~ $pattern } else { false }
      let hits = if $hit { [{path: $p, value: $item}] } else { [] }
      let children = if (not $is_prim) { $item | search-recurse $pattern $p } else { [] }
      $hits | append $children
    } | flatten
  } else {
    []
  }
}

# Search a data structure for a pattern and explore the match
#
# Recursively searches keys and primitive values using =~ (regex match).
# Presents all matches in sk, then starts explore on the selected one.
# Esc (or no matches) returns the input data unchanged.
@search-terms telescope find search grep
@example "find in pipeline" { open manifest.json | telescope find "redis" }
@example "find in file" { telescope find "redis" manifest.json }
export def find [
  query: string    # Pattern to search for (regex)
  file?: path      # File to open and search
]: any -> any {
  let data = if ($file | is-not-empty) { 
    open $file 
  } else if ($in | is-not-empty) {
    $in 
  } else {
    error make --unspanned "you must either specify a file or pipe something to stdin"
  }

  let results = ($data | search-recurse $query "")
  if ($results | is-empty) {
    return $data
  }
  let selected = try {
    ($results | choose {prompt: "find", display: {|| $in.path }, preview: {|width| $in.value | preview-of $width }})
  } catch { [] }
  if ($selected | is-empty) { return $data }
  let item = $selected | get value
  $item | explore
}

@search-terms telescope inspect browse explore fuzzy
@example "inspect a record" { {name: "alice", age: 30, hobbies: [reading coding]} | telescope explore }
@example "inspect a table" { [[name age]; [alice 30] [bob 25]] | telescope explore }
@example "open a file" { telescope explore manifest.json }
@example "skip column prompt" { [[name age]; [alice 30] [bob 25]] | telescope explore --primary-key name }
export def explore [
  file?: path                 # File to open and explore
  --primary-key (-k): string  # Column to use as display key for tables (skips prompt)
]: any -> any {
  mut current = if ($file | is-not-empty) {
    open $file 
  } else if ($in | is-not-empty) {
    $in 
  } else {
    error make --unspanned "you must either specify a file or pipe something to stdin"
  }

  loop {
    let type = ($current | describe)

    # Primitive types — return immediately
    if ($type in ["string" "int" "float" "bool" "duration" "filesize" "datetime" "nothing" "binary"]) {
      return $current
    }

    # Record — fuzzyfind over keys, preview values
    if ($type | str starts-with "record") {
      let pairs = ($current | transpose key value)
      let selected = try {
        ($pairs | choose {prompt: "record", display: {|| $in.key }, preview: {|width| $in.value | preview-of $width }})
      } catch {
        []
      }

      if ($selected | is-empty) {
        return $current
      }
      $current = ($selected | get value)
      continue
    }

    # Table — prompt for display column, fuzzyfind over rows
    if ($type | str starts-with "table") {
      let pk = if ($primary_key != null) {
        $primary_key
      } else {
        # A closure cannot capture a `mut` binding, and the preview needs the
        # rows to show what a column actually holds — so pin them first.
        let rows = $current
        let cols = ($current | columns)
        try {
          ($cols | choose {
            prompt: "display column"
            display: {|| $in }
            preview: {|width| let col = $in; $rows | get $col | first 20 | wrap $col | preview-of $width }
          })
        } catch {
          null
        }
      }

      if ($pk == null) {
        return $current
      }

      let selected = try {
        ($current | choose {prompt: $pk, display: {|| $in | get $pk | to text }, preview: {|width| $in | preview-of $width }})
      } catch {
        []
      }

      if ($selected | is-empty) {
        return $current
      }
      $current = $selected
      continue
    }

    # Plain list — fuzzyfind over items
    if ($type | str starts-with "list") {
      let selected = try {
        ($current | choose {prompt: "list", display: {|| $in | to text }, preview: {|width| preview-of $width }})
      } catch {
        []
      }

      if ($selected | is-empty) {
        return $current
      }
      $current = $selected
      continue
    }

    # Unknown type — return as-is
    return $current
  }
}
