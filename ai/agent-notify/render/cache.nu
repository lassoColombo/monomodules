# The last painted model, cached off-bar. An unchanged paint must cost zero IPC,
# so what the bar currently shows is remembered on disk rather than queried back
# from SketchyBar. `scaffold` drops the cache, so a bar reload always repaints
# from scratch.

def cache-file [] {
    let base = if ($env.XDG_CACHE_HOME? | is-not-empty) { $env.XDG_CACHE_HOME } else { [$env.HOME .cache] | path join }
    [$base sketchybar agents-model.json] | path join
}

# The cached model as raw JSON, or null when there is none / it is unreadable.
export def load [] {
    let f = cache-file
    if ($f | path exists) { try { open --raw $f | str trim } catch { null } } else { null }
}

export def put [json: string] {
    let f = cache-file
    let d = $f | path dirname
    if not ($d | path exists) { mkdir $d }
    $json | save --force $f
}

export def clear [] { let f = cache-file; if ($f | path exists) { rm --force $f } }
