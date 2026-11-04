def config []: nothing -> record {
  let config = $env.grafana_dashboard_config? | default {}
  for field in [url token] {
    if ($config | get -o $field | is-empty) {
      error make --unspanned {msg: $"set $env.grafana_dashboard_config.($field), see the readme"}
    }
  }
  $config
}

def endpoint [path: string]: nothing -> string {
  $"((config).url | str trim --right --char '/')($path)"
}

def auth-headers []: nothing -> record {
  {Authorization: $"Bearer ((config).token)"}
}

# Grafana answers errors with {message}, proxies in front of it with text.
def failure [method: string, path: string, response: record] {
  let reason = if ($response.body | describe) =~ '^record' { $response.body.message? } else { $response.body }
  error make --unspanned {msg: $"($method) ($path): HTTP ($response.status) ($reason)"}
}

# The body of a GET, or null when Grafana has nothing at that path.
def fetch [path: string]: nothing -> any {
  let response = http get --full --allow-errors --headers (auth-headers) (endpoint $path)
  match $response.status {
    200 => $response.body
    404 => null
    _ => (failure GET $path $response)
  }
}

# A token belongs to one org and reads and writes there, whatever url it is sent to.
def assert-org []: nothing -> nothing {
  let expected = (config).org?
  if $expected == null { return }
  let token_org = fetch /api/org
  if $token_org.id != $expected {
    error make --unspanned {msg: $"the token belongs to org ($token_org.id) \(($token_org.name)\), the config expects ($expected)"}
  }
}

# The id belongs to the instance and the version to its history: neither travels with the file.
def without-instance-fields []: record -> record {
  $in | upsert id null | reject -o version
}

def dashboards []: nothing -> table<uid: string, title: string, folder: string> {
  fetch "/api/search?type=dash-db&limit=5000"
  | each {|it| {uid: $it.uid, title: $it.title, folder: ($it.folderTitle? | default "General")} }
}

def uid-completer [] {
  {
    completions: (try { dashboards } catch { [] } | each {|it| {value: $it.uid, description: $"($it.title) \(($it.folder)\)"} })
    options: {completion_algorithm: "fuzzy", match_description: true, sort: false}
  }
}

def folder-completer [] {
  {
    completions: (try { fetch "/api/search?type=dash-folder&limit=5000" } catch { [] } | each {|it| {value: $it.uid, description: $it.title} })
    options: {completion_algorithm: "fuzzy", match_description: true, sort: false}
  }
}

# Save a Grafana dashboard into a file, in a form that can be pushed back to any instance.
export def pull [
  uid: string@uid-completer  # the dashboard to download
  file: path                 # where to write its JSON, overwriting it
]: nothing -> record<uid: string, version: int, file: path> {
  assert-org
  let envelope = fetch $"/api/dashboards/uid/($uid)"
  if $envelope == null { error make --unspanned {msg: $"no dashboard with uid ($uid) in ((config).url)"} }

  $"($envelope.dashboard | without-instance-fields | to json --indent 2)\n" | save --force $file
  {uid: $uid, version: $envelope.meta.version, file: ($file | path expand)}
}

# Upload a dashboard file to Grafana, over the dashboard with the same uid if there is one.
export def push [
  file: path                          # the dashboard JSON to upload
  --folder: string@folder-completer  # folder uid: where a new dashboard goes, or where an existing one moves to
  --message: string                  # note for Grafana's version history
]: nothing -> record<uid: string, version: int, url: string, created: bool> {
  let dashboard = open --raw $file | from json
  if ($dashboard.uid? | is-empty) {
    error make --unspanned {msg: $"($file) has no uid: Grafana would make one up, and every push would create another dashboard"}
  }
  assert-org

  # without a folder Grafana moves the dashboard to General, so an existing one keeps its own
  let existing = fetch $"/api/dashboards/uid/($dashboard.uid)"
  let body = {
    dashboard: ($dashboard | without-instance-fields)
    folderUid: ($folder | default $existing.meta?.folderUid? | default "")
    overwrite: true
    message: ($message | default $"pushed from ($file | path basename)")
  }
  let response = http post --full --allow-errors --headers (auth-headers) --content-type application/json (endpoint /api/dashboards/db) $body
  if $response.status != 200 { failure POST /api/dashboards/db $response }

  {uid: $dashboard.uid, version: $response.body.version, url: (endpoint $response.body.url), created: ($existing == null)}
}

# List the dashboards the token can see: what pull completes on.
export def ls []: nothing -> table<uid: string, title: string, folder: string> { dashboards }
