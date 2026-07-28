use std/math
# Generate the `# Commands` section of a module's README as Markdown, straight
# from the metadata that `scope commands` exposes. Produces a scannable overview
# table followed by one rich detail block per command: full description, a
# compact metadata line (signature, category, constness), a Parameters table for
# positional arguments, a Flags table for named/switch options — both carrying
# type and default — search terms, and runnable examples with their expected
# results. Tables are rendered with the builtin `to md`.
#
# `scope commands` only lists what is currently in scope, so the module you want
# to document must already be imported when this runs:
#
#   use semver
#   use readme-commands-section-generator
#   readme-commands-section-generator generate semver
#
# Write it straight to a file in one shot:
#
#   readme-commands-section-generator generate semver | save --force commands.md
#
# ---------------------------------------------------------------------------
# Sanitizing cell text for `to md`
#
# `to md` already escapes the two characters that are structural inside a GFM
# table cell — on its own it turns `\` into `\\` and `|` into `\|` — but it does
# NOT touch embedded newlines, and a raw newline splits the row and breaks the
# table. So the only sanitization we owe each cell before handing it to `to md`
# is collapsing it onto one line; escaping is `to md`'s job, and pre-escaping
# here would double-escape (a `\|` would come back out as `\\\|`).
#
# Backticks, brackets and parens pass through `to md` untouched, so the inline
# code spans (`md-code`) and anchor links we build below survive intact. Prose
# *outside* a table cell (a description paragraph, an example block) is authored
# markdown and is left alone apart from being collapsed onto one line; fenced
# example blocks get `md-fence` instead so their content can't close them early.
# ---------------------------------------------------------------------------

# Collapse newlines and whitespace runs into single spaces (one-line prose).
# For table cells, where a literal newline would split the row.
def str-oneline []: string -> string {
    $in | str replace --all --regex '\s+' ' ' | str trim
}

# Normalize a free-form prose field (a description / extra_description) for
# rendering as Markdown body text, PRESERVING the authored line structure.
# Markdown otherwise soft-wraps a lone newline into a space, so every in-section
# newline is turned into a hard line break (two trailing spaces + newline) and
# it renders exactly where the author put it. Blank-line section breaks (a bare
# comment line in the source) are kept as paragraph breaks. Per line we collapse
# internal whitespace runs and trim the edges, so stray indentation can't leak
# trailing spaces or trip Markdown's 4-space code-block rule.
def str-prose []: string -> string {
    $in
    | str trim
    | split row --regex '\n[ \t]*\n'
    | each {|section|
        $section
        | lines
        | each {|l| $l | str replace --all --regex '[ \t]+' ' ' | str trim }
        | where {|l| $l != '' }
        | str join $"  (char newline)"
    }
    | where {|s| $s != '' }
    | str join $"(char newline)(char newline)"
}

# Re-flow a captured code example to its natural indentation. Examples authored
# inside an `@example` block keep their source nesting, and the *opening* line
# often loses its leading indent while the body keeps it — e.g. a `[` at column
# 0 with its items at 8 spaces and the closing `]` at 4. A plain common-prefix
# dedent can't fix that (the prefix is 0), so we ignore the first line when it
# is the lone least-indented line, dedent the rest to that floor, and only ever
# strip leading whitespace (never content) from each line.
def code-dedent []: string -> string {
    let raw = $in | str trim --char (char newline)
    let lines = $raw | lines | each {|l| $l | str replace --regex '\s+$' '' }
    let nonblank = $lines | where {|l| ($l | str trim) != '' }
    if ($nonblank | length) <= 1 { return ($raw | str trim) }
    let indents = $nonblank | each {|l| ($l | str length) - ($l | str trim --left | str length) }
    let first = $indents | first
    let rest_min = $indents | skip 1 | math min
    let base = if $first < $rest_min { $rest_min } else { $indents | math min }
    $lines | each {|l| $l | str replace --regex $'^ {0,($base)}' '' } | str join (char newline)
}

# Length of the longest run of consecutive backticks (0 when there are none).
def backtick-run []: string -> int {
    $in
    | parse --regex '(?<run>`+)'
    | get run
    | each {|r| $r | str length }
    | append 0
    | math max
}

# A string of `n` backticks.
def backticks [n: int]: nothing -> string {
    0..<$n | each { '`' } | str join
}

# Wrap text as an inline code span, CommonMark-correct for any content: the
# delimiter is one backtick longer than the longest interior run, and a single
# padding space is added on each side when the content starts or ends with a
# backtick (the renderer strips one space back off).
def md-code []: string -> string {
    let text = $in
    let fence = backticks (($text | backtick-run) + 1)
    let padded = ($text | str starts-with '`') or ($text | str ends-with '`')
    let body = if $padded { $" ($text) " } else { $text }
    $"($fence)($body)($fence)"
}

# Wrap content in a fenced code block whose fence is long enough that nothing
# inside can close it early (at least three backticks).
def md-fence [lang: string]: string -> string {
    let content = $in
    let fence = backticks ([3 (($content | backtick-run) + 1)] | math max)
    [$"($fence)($lang)" $content $fence] | str join (char newline)
}

# GitHub heading-anchor slug: lowercase, drop everything but word characters,
# spaces and hyphens, then collapse space runs into single hyphens.
def gh-anchor []: string -> string {
    $in
    | str lowercase
    | str replace --all --regex '[^\w\s-]' ''
    | str trim
    | str replace --all --regex '\s+' '-'
}

# First sentence of an already-one-lined string, for the compact overview cell.
# A lone sentence is returned unchanged (the regex needs a `. ` separator).
def first-sentence []: string -> string {
    $in | str replace --regex '^(.*?\.)\s.*$' '$1'
}

# `input -> output` type strings for a command, scalar signatures before list.
def signatures-of []: record -> list<string> {
    $in.signatures
    | transpose key rows
    | sort-by {|s| $s.key | str starts-with 'list<' }
    | each {|s|
        let input = $s.rows | where parameter_type == 'input' | get 0?.syntax_shape | default 'any'
        let output = $s.rows | where parameter_type == 'output' | get 0?.syntax_shape | default 'any'
        $"($input) -> ($output)"
    }
}

# Backtick-wrap each signature variant and join them with ` / `.
def render-sig []: list<string> -> string {
    $in | each {|s| $s | md-code } | str join ' / '
}

# Drop columns whose every cell is blank, so `to md` never renders an empty
# column for a field that no row in the set actually provides (e.g. a Default
# column where nothing carries a default).
def drop-empty-columns []: table -> table {
    let rows = $in
    let keep = $rows | columns | where {|col| $rows | any {|r| ($r | get $col) != '' } }
    if ($keep | is-empty) { $rows } else { $rows | select ...$keep }
}

# Positional / flag / rest parameters, deduped across a command's signatures,
# in declaration order (the order you'd read them in `--help`).
def parameters-of []: record -> table {
    $in.signatures
    | values
    | flatten
    | where parameter_type in [positional named switch rest]
    | uniq-by parameter_name
}

# A flag's invocation token: the long name as an inline code span, with the
# short alias appended (also code-spanned) when one exists — `--out`, `-o`.
def flag-token []: record -> string {
    let row = $in
    let long = $"--($row.parameter_name)" | md-code
    if ($row.short_flag | is-not-empty) {
        $"($long), ($"-($row.short_flag)" | md-code)"
    } else {
        $long
    }
}

# The invocation token for a parameter, as an inline code span — no type shape
# (the Type column carries that). Positionals show a trailing `?` when optional
# and a leading `...` for rest; flags defer to `flag-token`.
def param-name []: record -> string {
    let row = $in
    match $row.parameter_type {
        'positional' => ((if $row.is_optional { $"($row.parameter_name)?" } else { $row.parameter_name }) | md-code),
        'rest' => ($"...($row.parameter_name)" | md-code),
        'named' | 'switch' => ($row | flag-token),
        _ => ($row.parameter_name | md-code),
    }
}

# The type shape of a parameter as an inline code span; switches take no value
# so they read as `switch`.
def param-type []: record -> string {
    let row = $in
    (if $row.parameter_type == 'switch' { 'switch' } else { $row.syntax_shape | default 'any' }) | md-code
}

# A parameter's default value as an inline code span (NUON, so the type shows),
# or blank when it has none.
def param-default []: record -> string {
    let d = $in.parameter_default
    if $d == null { '' } else { $d | to nuon | md-code }
}

# Render a parameter table (Type / Default columns auto-dropped when nothing in
# the set populates them). `head` names the first column — "Parameter" for
# positionals, "Flag" for options.
def param-table [head: string]: table -> string {
    $in
    | each {|p|
        {
            $head: ($p | param-name)
            Type: ($p | param-type)
            Default: ($p | param-default)
            Description: ($p.description | str-oneline)
        }
    }
    | drop-empty-columns
    | to md --pretty
}

# Render a command's runnable examples as one fenced `nu` block: each example is
# its description as a comment, the (re-flowed) code, and its expected result
# via `to nuon`.
def render-examples []: list -> string {
    $in
    | each {|e|
        [
            (if ($e.description | is-empty) { null } else { $"# ($e.description | str-oneline)" })
            ($e.example | code-dedent)
            (if ($e.result == null) { null } else { $"# => ($e.result | to nuon)" })
        ]
        | compact
        | str join (char newline)
    }
    | str join $"(char newline)(char newline)"
    | md-fence 'nu'
}

# Build the `# Commands` section for a module: a scannable overview table plus
# one rich detail block per command.
export def generate [
    module: string   # module whose commands to document (must already be `use`d)
]: nothing -> string {
    let cmds = scope commands
        | where {|c| $c.name == $module or ($c.name | str starts-with $"($module) ") }
        | sort-by name

    if ($cmds | is-empty) {
        error make { msg: $"no commands found for module '($module)' — did you `use ($module)` first?" }
    }

    # Overview: one scannable row per command. Record keys become the table
    # headers; `\(` / `\)` keep the link's parens literal (an unescaped `(`
    # inside a `$"..."` would open an interpolation expression).
    let overview = $cmds | each {|c|
        {
            Command: $"[($c.name | md-code)]\(#($c.name | gh-anchor)\)"
            Signature: ($c | signatures-of | render-sig)
            Description: ($c.description | str-oneline | first-sentence)
        }
    }

    # One detail block per command, assembled section by section.
    let details = $cmds | each {|c|
        mut lines = [$"### ($c.name | md-code)"]

        let desc = $c.description | str-prose
        if ($desc | is-not-empty) {
            $lines = $lines | append ['' $desc]
        }

        if ($c.extra_description | is-not-empty) {
            $lines = $lines | append ['' ($c.extra_description | str-prose)]
        }

        # Compact metadata line: signature, then category / type / constness —
        # each only when it actually carries information (type is omitted for
        # the usual `custom`), joined with a middle dot.
        mut meta = []
        let sig = $c | signatures-of | render-sig
        if ($sig | is-not-empty) { $meta = $meta | append $"**Signature:** ($sig)" }
        if ($c.category | is-not-empty) { $meta = $meta | append $"**Category:** ($c.category | md-code)" }
        if ($c.type != 'custom') { $meta = $meta | append $"**Type:** ($c.type | md-code)" }
        if $c.is_const { $meta = $meta | append '**Const**' }
        if ($meta | is-not-empty) {
            $lines = $lines | append ['' ($meta | str join ' · ')]
        }

        let params = $c | parameters-of
        let positionals = $params | where parameter_type in [positional rest]
        if ($positionals | is-not-empty) {
            $lines = $lines | append ['' '**Parameters**' '' ($positionals | param-table Parameter)]
        }

        let flags = $params | where parameter_type in [named switch]
        if ($flags | is-not-empty) {
            $lines = $lines | append ['' '**Flags**' '' ($flags | param-table Flag)]
        }

        if ($c.search_terms | is-not-empty) {
            let terms = $c.search_terms | split row ', ' | each {|t| $t | md-code } | str join ', '
            $lines = $lines | append ['' $"**Search terms:** ($terms)"]
        }

        if ($c.examples | is-not-empty) {
            $lines = $lines | append ['' '**Examples**' '' ($c.examples | render-examples)]
        }

        $lines | str join (char newline)
    }

    # Heading + overview table, then the detail blocks, every section separated
    # by a blank line. A trailing newline closes the file cleanly.
    let blank = $"(char newline)(char newline)"
    [
        (['## Commands' '' ($overview | drop-empty-columns | to md --pretty)] | str join (char newline))
        ($details | str join $blank)
    ]
    | str join $blank
    | $"($in)(char newline)"
}
