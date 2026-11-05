# grafana-dashboard

Keep Grafana dashboards as files: download one into a JSON file, upload a JSON file over the
dashboard with the same uid.

```nu
grafana-dashboard pull my-dashboard dashboards/my-dashboard.json   # Grafana -> file
grafana-dashboard pull --all dashboards                            # every dashboard -> a directory
grafana-dashboard push dashboards/my-dashboard.json                # file -> Grafana
grafana-dashboard push dashboards/new.json --folder ops            # a new one, into a folder
grafana-dashboard push dashboards/my-dashboard.json --force        # over changes made since the pull
grafana-dashboard ls                                               # what the token can see
$query | grafana-dashboard format-query                            # a MetricsQL query, formatted
```

The uid is the dashboard's identity on both sides: `pull` asks for it, `push` reads it from the
file and refuses a file without one, since Grafana would make one up and every push would leave
another copy behind. Tab completes the uid of `pull` with the dashboards the token can see, each
described by its title and folder, and the `--folder` of `push` with the folders.

A file belongs to one dashboard on one Grafana. `pull` writes it with the version it downloaded,
the one the next push builds on, and without `id`, the instance's own key for what the uid
already names.

`pull --all` downloads every dashboard the token can see into a directory, and returns a table
with a `status` per dashboard. A dashboard that already has a file anywhere under that directory,
found by its uid, is written over that file, so a name chosen by hand stays; any other goes to
`<folder>/<title>.json`, folder and title lower-cased with dashes, nested folders as nested
directories, General as `general`, and the folder's name dropped from the front of the title
(`Dumbo - Jobs` in Dumbo becomes `dumbo/jobs.json`). A dashboard moved to another folder in
Grafana keeps its old file, and a file whose dashboard is gone is left alone.

`push` sends the file's version and lets Grafana refuse it when the dashboard has a different
one, which means someone saved it after the file was pulled or last pushed: the push fails with
HTTP 412 and Grafana keeps what it has. Pull the dashboard into another file to see what changed,
bring those changes into yours, then push it with `--force`, which overwrites whatever Grafana
has.

After a push the file carries the version Grafana saved. Only its `version` line changes when it
has one at the top level; otherwise `push` rewrites the file the way `pull` lays it out. Every
push is a version in Grafana's history, `--message` writes its note, and the dashboard settings
restore any earlier one. An existing dashboard stays in its folder unless `--folder` moves it; a
new one goes to `--folder`, or to General.

Every command returns a record and prints nothing:

```nu
grafana-dashboard push dashboards/my-dashboard.json
# => {uid: my-dashboard, version: 13, url: https://grafana.example.com/d/my-dashboard/my-dashboard, created: false}
```

Grafana keeps the content of a pushed dashboard but not always the order of its keys, so the
first pull over a hand-written file may move lines around. Nushell compares records regardless
of key order, so it can tell whether anything really changed:

```nu
grafana-dashboard pull my-dashboard /tmp/live.json
(open dashboards/my-dashboard.json | reject version) == (open /tmp/live.json | reject version)
```

## Format a query

`format-query` formats a MetricsQL query with `metricsql.Prettify`, the printer VictoriaMetrics
puts behind vmui's Prettify button. VictoriaMetrics ships it only as a Go function, so
`metricsql-fmt/` wraps it in a program that reads stdin; the first call compiles it into
nushell's cache dir, and every call after a change to its source compiles it again.

```nu
"max by (host) (disk_used_percent) > 90" | grafana-dashboard format-query
# => max(disk_used_percent) by(host) > 90
```

It prints the query back from its parse tree instead of laying out the text you wrote: every
binary operation gets its parentheses, `by` moves after the aggregation, `-86400` becomes
`(0 - 86400)` and `WITH` templates are expanded. The meaning never changes, the text does.
MetricsQL is backwards compatible with PromQL, so it formats PromQL as well.

## Configure

```nu
$env.grafana_dashboard_config = {
  url: "https://grafana.example.com"
  token: "glsa_..."
  org: 42
}
```

`token` is a service account token: Viewer is enough for `pull` and `ls`, `push` needs Editor
on the folders it writes to. Without one, `user` and `password` log in as you, with your own
permissions, through basic auth: Grafana accepts the same credentials as its login form,
LDAP ones included, unless basic auth is turned off.

```nu
$env.grafana_dashboard_config = {
  url: "https://grafana.example.com"
  user: "me"
  password: "..."
  org: 42
}
```

`org` is the org to work in, sent with every request. A token can only work in its own org, a
user in any org it belongs to; either way every command first checks that Grafana agrees, since
in the wrong org `pull` finds nothing and `push` creates the dashboard in the wrong place.
Leave it out to work in the token's org, or in the user's current one.

`token` and `password` can also be closures that return them, called only when a request needs
them. That keeps them out of the environment and out of a config file kept in git, for example
in the macOS Keychain:

```nu
# once: security add-generic-password -s grafana-dashboard -a $env.USER -w
$env.grafana_dashboard_config.token = {|| ^security find-generic-password -s grafana-dashboard -w }
```

## Installation

```nu
# with this directory in one of your NU_LIB_DIRS
use grafana-dashboard
```

`format-query` needs Go 1.24 or later on the `PATH`.
