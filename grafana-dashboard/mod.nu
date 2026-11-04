const formatter_source = path self metricsql-fmt

def config []: nothing -> record {
  let config = $env.grafana_dashboard_config? | default {}
  if ($config.url? | is-empty) {
    error make --unspanned {msg: "set $env.grafana_dashboard_config.url, see the readme"}
  }
  if ($config.token? | is-empty) and (($config.user? | is-empty) or ($config.password? | is-empty)) {
    error make --unspanned {msg: "set $env.grafana_dashboard_config.token, or user and password, see the readme"}
  }
  $config
}

def endpoint [path: string]: nothing -> string {
  $"((config).url | str trim --right --char '/')($path)"
}

# A closure keeps a secret out of the environment until a request needs it.
def secret [field: string]: nothing -> string {
  let value = config | get $field
  let value = if ($value | describe) =~ '^closure' {
    try { do $value } catch {|err| error make --unspanned {msg: $"the ($field) closure failed: ($err.msg)"} }
  } else { $value }
  $value | str trim
}

def auth-headers []: nothing -> record {
  let config = config
  let authorization = if ($config.token? | is-not-empty) {
    $"Bearer (secret token)"
  } else {
    let credentials = $"($config.user):(secret password)" | encode base64
    $"Basic ($credentials)"
  }
  # a token works in its own org, a user in its current one unless the request names another
  let org_header = if $config.org? != null { {"X-Grafana-Org-Id": ($config.org | into string)} } else { {} }
  {Authorization: $authorization} | merge $org_header
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

# Save a Grafana dashboard into a file, with the version the next push of that file builds on.
export def pull [
  uid: string@uid-completer  # the dashboard to download
  file: path                 # where to write its JSON, overwriting it
]: nothing -> record<uid: string, version: int, file: path> {
  assert-org
  let envelope = fetch $"/api/dashboards/uid/($uid)"
  if $envelope == null { error make --unspanned {msg: $"no dashboard with uid ($uid) in ((config).url)"} }

  # the id is the instance's own key, and the uid already names the dashboard
  let dashboard = $envelope.dashboard | upsert id null | upsert version $envelope.meta.version
  $"($dashboard | to json --indent 2)\n" | save --force $file
  {uid: $uid, version: $envelope.meta.version, file: ($file | path expand)}
}

# Write the version Grafana saved into the file: only its line when the file has one at the top
# level, otherwise the whole file, laid out as pull writes it.
def save-version [file: path, version: int]: nothing -> nothing {
  let text = open --raw $file
  let expected = $text | from json | upsert version $version
  # the first key's indent is every top-level key's indent
  let indent = $text | parse --regex '^\{[ \t]*\r?\n(?<indent>[ \t]*)"' | get 0?.indent
  let edited = if $indent != null {
    $text | str replace --regex ('(?m)^' + $indent + '"version": *\d+') $'($indent)"version": ($version)'
  }
  if $edited != null and (try { $edited | from json } catch { null }) == $expected {
    $edited | save --force $file
  } else {
    $"($expected | to json --indent 2)\n" | save --force $file
  }
}

# Upload a dashboard file to Grafana as the next version of the one it was pulled from.
export def push [
  file: path                          # the dashboard JSON to upload
  --folder: string@folder-completer  # folder uid: where a new dashboard goes, or where an existing one moves to
  --message: string                  # note for Grafana's version history
  --force                            # overwrite the dashboard even if it has changed since the file was pulled
]: nothing -> record<uid: string, version: int, url: string, created: bool> {
  let dashboard = open --raw $file | from json
  if ($dashboard.uid? | is-empty) {
    error make --unspanned {msg: $"($file) has no uid: Grafana would make one up, and every push would create another dashboard"}
  }
  assert-org

  # without a folder Grafana moves the dashboard to General, so an existing one keeps its own
  let existing = fetch $"/api/dashboards/uid/($dashboard.uid)"
  let body = {
    dashboard: ($dashboard | upsert id null)
    folderUid: ($folder | default $existing.meta?.folderUid? | default "")
    overwrite: $force
    message: ($message | default $"pushed from ($file | path basename)")
  }
  let response = http post --full --allow-errors --headers (auth-headers) --content-type application/json (endpoint /api/dashboards/db) $body
  if $response.status != 200 { failure POST /api/dashboards/db $response }

  save-version $file $response.body.version

  {uid: $dashboard.uid, version: $response.body.version, url: (endpoint $response.body.url), created: ($existing == null)}
}

# The formatter binary, rebuilt whenever its source is newer than it.
def formatter []: nothing -> path {
  let binary = $nu.cache-dir | path join grafana-dashboard metricsql-fmt
  # %ls: the module's own ls shadows the builtin here
  let source_modified = %ls $formatter_source | get modified | math max
  if not ($binary | path exists) or (%ls $binary | get 0.modified) < $source_modified {
    mkdir ($binary | path dirname)
    let build = ^go -C $formatter_source build -o $binary . | complete
    if $build.exit_code != 0 {
      error make --unspanned {msg: $"could not build the formatter: ($build.stderr | str trim)"}
    }
  }
  $binary
}

# Format a MetricsQL query with metricsql.Prettify, the printer behind vmui's Prettify button.
export def format-query []: string -> string {
  let formatted = $in | run-external (formatter) | complete
  if $formatted.exit_code != 0 { error make --unspanned {msg: ($formatted.stderr | str trim)} }
  $formatted.stdout | str trim --right
}

# List the dashboards the token can see: what pull completes on.
export def ls []: nothing -> table<uid: string, title: string, folder: string> {
  assert-org
  dashboards
}
