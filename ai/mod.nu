# ai — structured content generation over the `claude` CLI, plus agent tooling.
#
#   ai generate <prompt> <schema>    — one-shot structured output (JSON schema)
#   ai review-loop <closure> <patt>  — interactive accept/edit/regenerate/quit
#   ai agent-notify <cmd>            — reflect agent state in zellij/SketchyBar
#
# Reusable, provider-agnostic, no git. Consumers (e.g. the `forge` module)
# import it via `use ../ai`.
export use generate.nu
export use review-loop.nu
export use agent-notify
