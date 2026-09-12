# Every client the module ships with — for DISCOVERY only.
#
# Listing a client here is not what makes it work: an agent's own configuration
# names its file directly, so a client file that nothing imports is fully
# functional the moment it exists. This module exists so `agent-notify clients`
# can show you what is available and how to wire each one up, and it is imported
# only by that cold command — never by an entry point, which imports exactly the
# one client it is for and pays for nothing else.
export use claude.nu
export use codex.nu
