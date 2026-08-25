# On/off switches for the counter animations, kept as flag files next to the
# model cache — one per counter, so `agents_anim`'s single tick knows which of
# the three it should be touching this second.
#
# They exist to make the animations RACE-FREE: the timer is stopped the instant
# a counter goes quiet, but a tick already running is mid-way through its frames
# and would repaint a beat later, leaving a stray clock face or a half-faded hue
# on a counter that has nothing to say. plugins/anim.sh re-reads the flags before
# every frame, so a run that outlives its animation drops the counters it no
# longer owns — and exits outright once it owns none.

def flag-dir [] {
    let base = if ($env.XDG_CACHE_HOME? | is-not-empty) { $env.XDG_CACHE_HOME } else { [$env.HOME .cache] | path join }
    [$base sketchybar] | path join
}

# Arm / disarm, one flag per counter. Idempotent; must be called BEFORE the
# message that flips the timer, so the abort is in place ahead of the tick it
# has to stop.
export def set [on: record<run: bool, stale: bool, attn: bool>] {
    let dir = flag-dir
    if not ($dir | path exists) { mkdir $dir }
    for k in ["run" "stale" "attn"] {
        let f = [$dir $"agents-anim.($k)"] | path join
        if ($on | get $k) {
            if not ($f | path exists) { "" | save --force $f }
        } else if ($f | path exists) { rm --force $f }
    }
}
