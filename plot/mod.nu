# Plot — charts from Nushell tables, drawn directly in the terminal.
#
# Each command consumes a table (`list<record>`) on stdin, builds a Vega-Lite
# spec, and renders it via the `vl-convert` CLI. The image is then drawn inline
# using the kitty graphics protocol — no external viewer, no window.
#
#   plot line       one or more y-series vs x, optionally smoothed
#   plot scatter    points
#   plot bar        categorical x; clustered / stacked / normalized
#   plot histogram  distribution of a single numeric column
#   plot step       step function (pre / post / mid)
#   plot impulses   vertical sticks
#
# Conventions:
#   • `-x` selects the x column; `--y` is a list of y columns.
#   • Wide input by default (each `--y` is a series). `--series <col>` takes
#     long/tidy input instead: one `--y` value column plus a column whose values
#     name the series — so grouped data pipes in without a manual pivot.
#   • With no flags the chart is drawn in this terminal, sized to the pane.
#   • `--out <file>` writes an image instead (png, jpg, svg, pdf, html by
#     extension) and never opens it.
#   • `--spec` returns the Vega-Lite spec instead of drawing anything.
#   • Column flags complete against the last table you plotted: `-x` offers every
#     column, `--y` only numeric ones, `--series` only the rest.
#
# Environment:
#   $env.PLOT_SIZE      "100x24" — override the inline size, in cells
#   $env.PLOT_CELL_PX   "20x53"  — override the terminal's cell size in pixels
#   $env.PLOT_STATE     where completion/render state lives
#   $env.PLOT_DEBUG     a path to dump the generated Vega-Lite spec to
#
# Requires `vl-convert` on PATH (https://github.com/vega/vl-convert) and a
# terminal that speaks the kitty graphics protocol (Ghostty, kitty, or
# zellij 0.45+ on top of one).

export use ./charts *
