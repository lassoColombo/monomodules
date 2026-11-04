# grafana-dashboard

Keep Grafana dashboards as files: download one into a JSON file, upload a JSON file over the
dashboard with the same uid.

```nu
grafana-dashboard pull my-dashboard dashboards/my-dashboard.json   # Grafana -> file
grafana-dashboard push dashboards/my-dashboard.json                # file -> Grafana
grafana-dashboard push dashboards/new.json --folder ops            # a new one, into a folder
grafana-dashboard ls                                               # what the token can see
```

The uid is the dashboard's identity on both sides: `pull` asks for it, `push` reads it from the
file and refuses a file without one, since Grafana would make one up and every push would leave
another copy behind. Tab completes the uid of `pull` with the dashboards the token can see, each
described by its title and folder, and the `--folder` of `push` with the folders.

`pull` writes the dashboard without `id` and `version`: the first belongs to the instance, the
second to its history, so a file pulled from one Grafana pushes cleanly to another, and pulling
the same dashboard twice gives the same file.

`push` overwrites whatever Grafana has under that uid, without asking. That is what Grafana's
version history is for: every push is a version, `--message` writes its note, and the dashboard
settings restore any earlier one. An existing dashboard stays in its folder unless `--folder`
moves it; a new one goes to `--folder`, or to General.

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
(open dashboards/my-dashboard.json | reject -o version) == (open /tmp/live.json)
```

## Configure

```nu
$env.grafana_dashboard_config = {
  url: "https://grafana.example.com"
  token: "glsa_..."
  org: 42
}
```

`token` is a service account token: Viewer is enough for `pull` and `ls`, `push` needs Editor
on the folders it writes to. A token belongs to one org and works there whatever url it is sent
to, so with a token of the wrong org `pull` finds nothing and `push` creates the dashboard in
the wrong place. Set `org` to the id you expect, and every command checks the token against it
before doing anything; leave it out to skip the check.

## Installation

```nu
# with this directory in one of your NU_LIB_DIRS
use grafana-dashboard
```
