# XDG-based paths for agent-notify's on-disk state. One JSON record per live
# agent instance lives under store-dir (see store.nu).

export def xdg-data-home [] {
    if ($env.XDG_DATA_HOME? | is-not-empty) { $env.XDG_DATA_HOME } else { [$env.HOME .local share] | path join }
}

# Directory holding one JSON record per live agent instance.
export def store-dir [] { [(xdg-data-home) agent-notify] | path join }

export def ensure-dir [dir: string] { if not ($dir | path exists) { mkdir $dir } }
