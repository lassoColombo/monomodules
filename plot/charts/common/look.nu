# The presentation flags every chart command shares.
#
# Nushell cannot compose command signatures, so each command must declare these
# flags itself. What it does NOT have to repeat is their meaning: every command
# hands them here as a record, and this is the only place that decides what they
# amount to.

# Normalise the common flags into the `look` record the renderer consumes.
export def common [flags: record]: nothing -> record {
    {
        title:      $flags.title?
        xlabel:     $flags.xlabel?
        ylabel:     $flags.ylabel?
        xrange:     $flags.xrange?
        yrange:     $flags.yrange?
        width:      ($flags.width?  | default 800)
        height:     ($flags.height? | default 600)
        grid:       ($flags.grid?   | default false)
        legend:     ($flags.legend? | default true)
        legend_pos: $flags.legend_pos?
        logx:       ($flags.logx? | default false)
        logy:       ($flags.logy? | default false)
        xformat:    $flags.xformat?
        yformat:    $flags.yformat?
        out:        $flags.out?
        spec:       ($flags.spec? | default false)
    }
}
