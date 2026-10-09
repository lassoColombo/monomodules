# zellij-session-switcher

Switch zellij session from the shell, with one command that does the right thing on both sides
of the fence: inside a session it moves the current client with `zellij action switch-session`,
outside it attaches with `zellij attach`.

```nu
zellij-session-switcher            # pick a session
zellij-session-switcher home       # switch to `home`
zellij-session-switcher ho         # switch to `home` too, if nothing else matches
zellij-session-switcher ls         # the sessions as a table
```

The argument is matched against the session names: an exact name wins, otherwise it is used as a
regex, and if it matches more than one session you are asked to choose. Pass nothing and you are
asked straight away. A name that matches nothing is an error - this switches between sessions,
it never creates one.

Autocompletion covers the same ground: Tab offers the live sessions, each with its state and age
as description, the current one in green and the exited ones dimmed. Descriptions need a menu
with room for them, so bind the ide menu if you want to see them on Tab.

`ls` returns what the switcher works on - `name`, `created` (a real duration, so you can sort by
it), `current` and `exited`:

```nu
zellij-session-switcher ls | where not exited | sort-by created
```

## Configure the picker

Choosing a session uses Nushell's built-in `input list` by default. Set
`$env.zellij_session_switcher_config.picker` to swap the engine. A picker is a closure from a
list of sessions to one session:

```
list<record<name: string, created: duration, current: bool, exited: bool>> -> record | null
```

`zellij-session-switcher ls` returns exactly those records, so a picker is a command you can run
by hand against real data:

```nu
$env.zellij_session_switcher_config = {picker: {|| $in | where not exited | first }}
```

Returning nothing cancels the switch.

Here is one real one, using [skim](https://github.com/lotabout/skim)'s Nushell plugin, previewing
the tabs of the session under the cursor - which is the question being asked, not "which session
is this" but "is the thing I am after in it":

```nu
$env.zellij_session_switcher_config = {picker: {||
  let sessions = $in
  let names = $sessions | get name | each {|it| $it | str length} | math max

  let preview = {||
    let session = $in
    if $session.exited { return "exited - switching resurrects it" }
    let r = ^zellij -s $session.name action list-tabs --panes --json | complete
    if $r.exit_code != 0 { return $r.stderr }
    $r.stdout | from json | each {|tab|
      let panes = $tab.selectable_tiled_panes_count + $tab.selectable_floating_panes_count
      $"(if $tab.active {"> "} else {"  "})($tab.name) ($panes)"
    } | str join (char newline)
  }

  let format = {||
    let state = if $in.current { "current" } else if $in.exited { "exited" } else { "" }
    let age = $in.created | into string | split row " " | first 2 | str join " "
    $"($in.name | fill -w $names) ($state | fill -w 7) ($age)"
  }

  $sessions | sk --format $format --preview $preview --preview-window "right:50%:wrap" --layout reverse --prompt "session "
}}
```

`zellij -s <name> action ...` is how a session other than the current one answers questions, so
the preview can show tabs you are not in. An exited session has no server to ask - it is still
worth switching to, since that resurrects it.

## Installation

```nu
# clone into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) zellij-session-switcher] | path join
git clone git@github.com:lassoColombo/zellij-session-switcher.git $dest

# use the module, and give it a shorter name while you are at it
use zellij-session-switcher
alias zs = zellij-session-switcher
```

Import the module, not its contents: `use zellij-session-switcher *` would put `ls` in your
scope on top of the built-in one.
