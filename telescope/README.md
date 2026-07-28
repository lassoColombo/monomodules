# telescope

An intuitive navigator for complex data structures in [Nushell](https://www.nushell.sh/).

[![asciicast](https://asciinema.org/a/IPueesBg18Qu0cy4.svg)](https://asciinema.org/a/IPueesBg18Qu0cy4)

Drill into deeply nested records, tables, and lists with fuzzy search — or grep across the whole structure and jump straight to a match. Powered by [`sk`](https://github.com/lotabout/skim) via [`nu_plugin_skim`](https://github.com/idanarye/nu_plugin_skim).

## Requirements

| Tool | Purpose |
|------|---------|
| [Nushell](https://www.nushell.sh/) | Host shell |
| [`nu_plugin_skim`](https://github.com/idanarye/nu_plugin_skim) | Provides the `sk` fuzzy finder |

## Installation

```nushell
# clone this repository into one of your NU_LIB_DIRS
let dest = [($env.NU_LIB_DIRS | first) telescope] | path join
git clone git@github.com:lassoColombo/telescope.git $dest

# use the module
use telescope
telescope --help
```

## Quick start

```nushell
use telescope

# Explore a file
telescope explore manifest.json

# Explore a pipeline value
open manifest.json | telescope explore

# Skip the column prompt for tables
ls | telescope explore --primary-key name

# Search by regex across keys and primitive values
open manifest.json | telescope find "redis"

# Search a file directly
telescope find "redis" manifest.json

# Compose into a pipeline — telescope returns whatever you stopped on
open manifest.json | telescope find "p99" | get target
open demo.yaml | get services | telescope explore -k name | get dependencies
```

## Commands

| Command | Description |
|---------|-------------|
| `telescope explore [file]` | Interactively walk a data structure |
| `telescope find <query> [file]` | Regex-search keys + primitive values, then explore the match |

Both commands accept input from a pipeline or from an optional file argument.

## Flags

### `telescope explore`

| Flag | Short | Description |
|------|-------|-------------|
| `--primary-key` | `-k` | Column to use as display key for tables (skips the prompt) |
| `--path` |  | Starting cell-path (used internally by `find` handoff) |

### `telescope find`

No flags beyond the positional `query` (regex) and optional `file`.

## Interactive keys

Inside the fuzzy picker:

| Key | Effect |
|-----|--------|
| `Enter` | Drill into the selected item |
| `Esc` | Stop here, return the current value unchanged |
| Type | Fuzzy filter the list |

Primitive values (strings, ints, floats, bools, dates, etc.) are returned immediately without a picker step.

## Behavior

- **Record** — fuzzy-find over keys; preview shows the value.
- **Table** — prompts once for a display column, then fuzzy-find over rows by that column; preview shows the row transposed as key/value pairs so wide rows stay readable.
- **List** — fuzzy-find over items directly.
- **Primitive** — returned immediately.

`find` recursively searches both keys and primitive values using `=~` (regex match), collects matches with their cell-paths, and hands the selected match off to `explore` so you can keep drilling from there.

Preview rendering uses `table --expand` sized to the actual preview pane width (computed from `term size`), so columns aren't truncated.

## Acknowledgments

- The [Nushell](https://www.nushell.sh/) team for making this possible.
- [idanarye/nu_plugin_skim](https://github.com/idanarye/nu_plugin_skim) for bringing fuzzy finding into Nu.
- [Telescope-Nvim](https://github.com/nvim-telescope/telescope.nvim) for the name (and because why not).
