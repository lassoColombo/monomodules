# forge — AI-assisted authoring for the current repo (git + glab/gh + ai).
# A submodule of gg; its commands are flattened to the gg top level
# (gg commit / gg mr / gg pr). Operates on the ONE repo you're in — distinct
# from the fleet commands. Generation lives in the standalone `ai` module.
export use commit.nu
export use mr.nu
export use pr.nu
