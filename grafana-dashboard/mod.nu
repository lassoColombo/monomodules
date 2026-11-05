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

def save-dashboard [uid: string, file: path]: nothing -> record<uid: string, version: int, file: path> {
  let envelope = fetch $"/api/dashboards/uid/($uid)"
  if $envelope == null { error make --unspanned {msg: $"no dashboard with uid ($uid) in ((config).url)"} }

  # the id is the instance's own key, and the uid already names the dashboard
  let dashboard = $envelope.dashboard | upsert id null | upsert version $envelope.meta.version
  $"($dashboard | to json --indent 2)\n" | save --force $file
  {uid: $uid, version: $envelope.meta.version, file: ($file | path expand)}
}

def slug []: string -> string {
  $in | str lowercase | str replace --all --regex '[^a-z0-9.]+' '-' | str trim --char '-'
}

# The directory of each folder, by uid: its title under its parents' when folders nest.
def folder-dirs []: nothing -> record {
  fetch "/api/search?type=dash-folder&limit=5000"
  | reduce --fold {} {|folder, dirs|
    let parents = fetch $"/api/folders/($folder.uid)" | get -o parents | default [] | each {|parent| $parent.title }
    $dirs | insert $folder.uid ($parents | append $folder.title | each { slug } | path join)
  }
}

# The dashboard files already under a directory, by uid.
def files-by-uid [dir: path]: nothing -> record {
  glob ($dir | path join "**" "*.json")
  | reduce --fold {} {|file, found|
    let uid = try { open --raw $file | from json | get -o uid } catch { null }
    if ($uid | describe) == string and ($uid | is-not-empty) { $found | upsert $uid $file } else { $found }
  }
}

# A file for a dashboard that has none yet: its title, without the folder's name when it starts with it.
def new-file [dir: path, title: string, uid: string, taken: list<path>]: nothing -> path {
  let prefix = $"($dir | path basename)-"
  let name = $title | slug
  let name = if ($name | str starts-with $prefix) and ($name | str length) > ($prefix | str length) {
    $name | str substring ($prefix | str length)..
  } else { $name }
  let name = if ($name | is-empty) { $uid } else { $name }
  let file = $dir | path join $"($name).json"
  if $file in $taken or ($file | path exists) { $dir | path join $"($name)-($uid).json" } else { $file }
}

# Every dashboard into `dir`: over the file that already has its uid, wherever it is, otherwise
# into a new file under its folder's directory.
def pull-all [dir: path]: nothing -> table<uid: string, version: int, file: path, status: string> {
  let dir = $dir | path expand
  let dirs = folder-dirs
  let known = files-by-uid $dir
  fetch "/api/search?type=dash-db&limit=5000"
  | reduce --fold [] {|it, pulled|
    let file = if $it.uid in $known { $known | get $it.uid } else {
      let folder = $dir | path join ($dirs | get -o ($it.folderUid? | default "") | default "general")
      new-file $folder $it.title $it.uid ($pulled | get -o file | default [] | append ($known | values))
    }
    mkdir ($file | path dirname)
    let status = if $it.uid in $known { "updated" } else { "new" }
    $pulled | append (save-dashboard $it.uid $file | insert status $status)
  }
}

# Save a Grafana dashboard into a file, with the version the next push of that file builds on.
export def pull [
  uid?: string@uid-completer  # the dashboard to download
  file?: path                 # where to write its JSON, overwriting it
  --all: path                 # download every dashboard into this directory instead, a subdirectory per folder
]: nothing -> any {
  if $all != null {
    if $uid != null { error make --unspanned {msg: "--all downloads every dashboard: give it a directory, not a uid"} }
    assert-org
    return (pull-all $all)
  }
  if $uid == null or $file == null { error make --unspanned {msg: "pull needs a uid and a file, or --all and a directory"} }
  assert-org
  save-dashboard $uid $file
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
