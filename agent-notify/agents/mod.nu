# Every agent the module ships with — for DISCOVERY only.
#
# Listing an agent here is not what makes it work: an agent's own configuration
# names its file directly, so an agent module that nothing imports is fully
# functional the moment it exists. This module exists so `agent-notify agents`
# can show you what is available and how to wire each one up, and it is imported
# only by that cold command — never by an entry point, which imports exactly the
# one agent it is for and pays for nothing else.
export use claude.nu
export use codex.nu
