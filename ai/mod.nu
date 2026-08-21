# ai — structured content generation over the `claude` CLI.
#
#   ai generate <prompt> <schema>    — one-shot structured output (JSON schema)
#   ai review-loop <closure> <patt>  — interactive accept/edit/regenerate/quit
#
# Reusable, provider-agnostic, no git. Consumers (e.g. the `forge` module)
# import it via `use ../ai`.
export use generate.nu
export use review-loop.nu
