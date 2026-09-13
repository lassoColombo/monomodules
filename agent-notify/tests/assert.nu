# The little that a test needs: compare, expect-an-error, and print a result.
#
# Deliberately not a framework. The suites are plain nushell scripts that build
# a list of results and hand it here, which means a suite can be read top to
# bottom as a description of what the module promises.

export def check [label: string, got: any, want: any]: nothing -> record {
    if $got == $want {
        {ok: true, label: $label}
    } else {
        {ok: false, label: $label, got: $got, want: $want}
    }
}

# An error is a result too: does this closure fail, and does it say why in terms
# the caller would recognise? Matching on the message keeps a test honest — a
# rule that fires for the wrong reason is not the rule we meant to write.
export def check-err [label: string, hint: string, code: closure]: nothing -> record {
    let r = try { do $code; {failed: false, msg: ""} } catch {|e| {failed: true, msg: $e.msg} }
    if $r.failed and ($r.msg | str contains $hint) {
        {ok: true, label: $label}
    } else {
        {ok: false, label: $label, got: $r, want: $"error containing '($hint)'"}
    }
}

# Print every result, then the tally and any failures in full. Returns true when
# everything passed, so a caller can chain suites and still fail loudly.
export def summarise [results: list<any>, --title: string = ""]: nothing -> bool {
    if ($title | is-not-empty) { print $"(ansi cyan)($title)(ansi reset)" }
    print ($results | each {|x| $"(if $x.ok { '  ok  ' } else { ' FAIL ' }) ($x.label)" } | str join "\n")
    let bad = $results | where ok == false
    print $"($results | where ok == true | length)/($results | length) passed"
    if ($bad | is-not-empty) { print ($bad | table --width 120) }
    print ""
    ($bad | is-empty)
}
