# launchd — the macOS launcher. `StartInterval` IS a clock.
#
# No daemon to keep alive, no lock file, no pid to supervise, and it survives
# logout and reboot. One file, one label, and `launchctl` to load and unload it.
#
# THE TRAP, and it cost real time: A JOB'S PATH IS `/usr/bin:/bin`. Every program
# a job calls needs an absolute path — this silently broke the repaint while the
# sweep worked fine, so the job "succeeded" every 30 seconds and painted nothing.
# `prune-command` in mod.nu names nu by `$nu.current-exe` for exactly that
# reason.
#
# See mod.nu for the contract these five exports implement, and for the rule
# about what a launcher may touch: this one owns the plist below and nothing
# else.

export const INFO = {name: "launchd", title: "macOS — a LaunchAgent with StartInterval"}
export const LABEL = "com.agent-notify.prune-daemon"

export def plist-path []: nothing -> string {
    $nu.home-dir | path join "Library" "LaunchAgents" $"($LABEL).plist"
}

def domain []: nothing -> string { $"gui/(^id -u | str trim)" }

# macOS, and a launchctl to talk to. Nothing else can be true here — there is no
# launchd anywhere else — so the probe is cheap and needs no subprocess to fail.
export def available []: nothing -> record {
    if $nu.os-info.name != "macos" {
        return {ok: false, why: $"launchd is macOS only, and this machine is ($nu.os-info.name)"}
    }
    if (which launchctl | is-empty) {
        return {ok: false, why: "launchctl is not on PATH"}
    }
    {ok: true, why: ""}
}

# PURE. One plist, and every argument of the tick reaches it verbatim.
export def unit-files [tick: list<string>, log: string, interval: int]: nothing -> table {
    let args = $tick | each {|a| $"        <string>($a)</string>" } | str join "\n"
    let text = ([ '<?xml version="1.0" encoding="UTF-8"?>'
       '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">'
       '<plist version="1.0">'
       '<dict>'
       '    <key>Label</key>'
       $"    <string>($LABEL)</string>"
       '    <key>ProgramArguments</key>'
       '    <array>'
       $args
       '    </array>'
       '    <key>StartInterval</key>'
       $"    <integer>($interval)</integer>"
       '    <key>RunAtLoad</key>'
       '    <true/>'
       '    <key>StandardErrorPath</key>'
       $"    <string>($log)</string>"
       '</dict>'
       '</plist>' ] | str join "\n")
    [{path: (plist-path), text: $text}]
}

# `bootout` first so re-installing picks up a changed interval or path. It fails
# when nothing is loaded, which is the normal case and not an error.
export def register []: nothing -> record {
    ^launchctl bootout $"(domain)/($LABEL)" | complete | ignore
    let r = ^launchctl bootstrap (domain) (plist-path) | complete
    {ok: ($r.exit_code == 0), why: (if ($r.exit_code == 0) { "" } else { $r.stderr | str trim })}
}

export def unregister []: nothing -> record {
    let r = ^launchctl bootout $"(domain)/($LABEL)" | complete
    {ok: ($r.exit_code == 0), why: (if ($r.exit_code == 0) { "" } else { $r.stderr | str trim })}
}

# `launchctl list` gives the pid (or `-` when it is between runs) and the last
# exit status, which is how a broken tick is noticed rather than silently doing
# nothing every 30 seconds.
export def status []: nothing -> record {
    let r = ^launchctl list | complete
    let line = if ($r.exit_code == 0) {
        $r.stdout | lines | where {|l| $l | str ends-with $LABEL } | get -o 0
    } else { null }
    let f = ($r.exit_code == 0) and ($line != null)
    let fields = if $f { $line | str trim | split row --regex '\s+' } else { [] }
    { installed: (plist-path | path exists)
      loaded: $f
      last_exit: (if $f { $fields.1 } else { "" })
      running_now: (if $f and ($fields.0 != "-") { true } else { false })
      interval: (interval-in-file) }
}

# Read the interval back OUT of the plist: the file is what launchd obeys, and
# what someone typed at install time is only a memory of it.
def interval-in-file []: nothing -> int {
    let f = plist-path
    if not ($f | path exists) { return 0 }
    let ls = open --raw $f | lines
    let m = $ls | enumerate | where {|l| $l.item | str contains "<key>StartInterval</key>" } | get -o 0
    if $m == null { return 0 }
    $ls | get ($m.index + 1) | str trim | str replace --all --regex '</?integer>' '' | into int
}
