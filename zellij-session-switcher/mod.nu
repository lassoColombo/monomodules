# Durations as zellij spells them when it lists sessions.
const age_units = {
  s: 1sec sec: 1sec secs: 1sec second: 1sec seconds: 1sec
  m: 1min min: 1min mins: 1min minute: 1min minutes: 1min
  h: 1hr hr: 1hr hrs: 1hr hour: 1hr hours: 1hr
  d: 1day day: 1day days: 1day
  w: 1wk wk: 1wk wks: 1wk week: 1wk weeks: 1wk
}

# "10days 9h 26m 51s" -> 1wk 3day 9hr 26min 51sec. Units we do not know are ignored.
def age [raw: string]: nothing -> duration {
  $raw
  | parse --regex '(?<amount>\d+)\s*(?<unit>[a-zA-Z]+)'
  | reduce --fold 0sec {|it, acc|
      let unit = $age_units | get -o ($it.unit | str lowercase)
      if $unit == null { $acc } else { $acc + (($it.amount | into int) * $unit) }
    }
}

# The two largest units of a duration: 1wk 3day 9hr 26min 51sec -> "1wk 3day".
def coarse [span: duration]: nothing -> string {
  $span | into string | split row " " | first 2 | str join " "
}

def sessions []: nothing -> table<name: string, created: duration, current: bool, exited: bool> {
  # zellij exits non zero only when it has nothing to list
  let listing = ^zellij list-sessions --no-formatting | complete
  if $listing.exit_code != 0 { return [] }

  $listing.stdout
  | lines
  | parse --regex '^(?<name>.+?) \[Created (?<age>.+?) ago\]\s*(?:\((?<status>[^)]*)\))?$'
  | each {|it|
      # the status group does not take part in the match when a session is just running
      let status = $it.status | default ""
      {
        name: $it.name
        created: (age $it.age)
        current: ($status | str starts-with "current")
        exited: ($status | str starts-with "EXITED")
      }
    }
}

def state []: record -> string {
  if $in.current { "current" } else if $in.exited { "exited" } else { "running" }
}

def session-completer [] {
  {
    completions: (sessions | each {|session| {
      value: $session.name
      description: $"($session | state), created ((coarse $session.created)) ago"
      style: (match ($session | state) {
        "current" => {fg: green attr: b}
        "exited" => {attr: d}
        _ => {attr: n}
      })
    }})
    options: {
      completion_algorithm: "fuzzy"
      match_description: true
      sort: false
    }
  }
}

def pick []: table -> any {
  let items = $in
  let custom = $env.zellij_session_switcher_config?.picker?
  if ($custom | is-not-empty) {
    $items | do $custom
  } else {
    $items | input list --fuzzy --display {|| $"($in.name) \(($in | state)\)" } "session"
  }
}

def choose [session?: string]: nothing -> any {
  let all = sessions
  if ($all | is-empty) { error make --unspanned {msg: "no zellij session to switch to"} }
  if ($session | is-empty) { return ($all | pick) }

  let exact = $all | where name == $session
  if ($exact | is-not-empty) { return $exact.0 }

  let matches = $all | where name =~ $session
  match ($matches | length) {
    0 => (error make --unspanned {msg: $"no zellij session matches ($session)"})
    1 => $matches.0
    _ => ($matches | pick)
  }
}

# Switch to another zellij session: inside zellij the current client moves to it, outside zellij it attaches to it.
export def main [
  session?: string@session-completer  # session name (regex against the session name)
] {
  let target = choose $session
  if ($target | is-empty) { return }

  if ($env.ZELLIJ? | is-not-empty) {
    ^zellij action switch-session $target.name
  } else {
    ^zellij attach $target.name
  }
}

# List the zellij sessions: what they are called, how long they have been around, how they stand.
export def ls []: nothing -> table<name: string, created: duration, current: bool, exited: bool> { sessions }
