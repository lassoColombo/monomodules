# ai — structured content generation over the `claude` CLI.
#
#   ai generate <prompt> <schema>    — one-shot structured output (JSON schema)
#   ai review-loop <closure> <patt>  — interactive accept/edit/regenerate/quit
#
# Reusable, provider-agnostic, no git. Consumers (e.g. the `forge` module)
# import it via `use ../ai`.
#
# `agent-notify` USED TO LIVE HERE and no longer does. It was never `ai`-shaped:
# nothing about reflecting agent state on a status bar is provider-agnostic
# content generation, and being a submodule meant every one of its hooks parsed
# the whole `ai` tree — the cost that started the rewrite. It is a module of its
# own now, alongside this one.
export use generate.nu
export use review-loop.nu
