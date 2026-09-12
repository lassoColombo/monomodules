# What a VALUE looks like in a preview pane — the thing telescope exists to show
# you, which is why picker.nu has no fallback to a picker that cannot draw one.

# Render a value for the preview pane. Records are transposed to a key/value
# table so wide rows don't get column-truncated; tables and lists render as-is.
# `width` is the pane's, handed over by the picker that owns it, so `table
# --expand` neither over-runs it nor leaves it half empty.
export def preview-of [width: int]: any -> any {
  let v = $in
  if (($v | describe) | str starts-with "record") {
    $v | transpose key value | table --expand --width $width
  } else {
    $v | table --expand --width $width
  }
}
