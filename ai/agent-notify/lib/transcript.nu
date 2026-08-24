# Fallback preview source: extract the last assistant TEXT from a Claude Code
# transcript (JSONL) when the Stop hook payload doesn't carry
# `last_assistant_message`. Each line is an event; assistant lines look like
# {type: "assistant", message: {content: [{type: "text", text: "..."}, ...]}}.
# tool_use / tool_result blocks carry no text and are skipped. "" if none.

export def last-message [path?: string] {
    if ($path | is-empty) { return "" }
    if not ($path | path exists) { return "" }
    # Only the tail matters — the final assistant text is near the end.
    let recent = try { open --raw $path | lines | last 200 } catch { return "" }
    $recent
    | reverse
    | each {|l| try { $l | from json } catch { null } }
    | compact
    | where {|o| ($o.type? | default "") == "assistant" }
    | each {|o|
        $o.message?.content?
        | default []
        | where {|b| ($b.type? | default "") == "text" }
        | each {|b| $b.text? | default "" }
        | str join " "
        | str trim
      }
    | where {|t| $t != "" }
    | get -o 0
    | default ""
}
