# Kitty graphics protocol: put a PNG on the screen.
#
# The image is transmitted BY PATH (t=f), not by base64-chunking its bytes inline
# — zellij 0.45 supports file transmission, which turns a ~280KB escape stream
# into ~50 bytes.
#
# We deliberately do NOT use t=t ("read then delete it for me"): terminals only
# honour that for paths they consider temporary, and `path expand` rewriting
# /tmp to /private/tmp is enough to fail that test. Cleanup is ours instead —
# see render/mod.nu. The terminal decodes the file immediately and keeps its own
# copy of the pixels (images survive scrollback and resize), so the file on disk
# is needed only for the instant it takes to read.

# The escape sequence that displays a PNG in a cols x rows cell box.
# Kept separate from `show` so it can be inspected and tested without a terminal.
export def escape [
    png: path,
    --cols: int,        # width of the cell box
    --rows: int,        # height of the cell box
    --id: int = 1,      # image id, so it can be replaced or deleted later
]: nothing -> string {
    let esc = char --integer 27
    let backslash = char --integer 92
    let payload = $png | path expand | encode base64
    $"($esc)_Ga=T,f=100,t=f,i=($id),c=($cols),r=($rows),q=2;($payload)($esc)($backslash)"
}

# Display a PNG at the cursor, scaled into a cols x rows cell box.
export def show [
    png: path,
    --cols: int,        # width of the cell box
    --rows: int,        # height of the cell box
    --id: int = 1,      # image id, so it can be replaced or deleted later
]: nothing -> nothing {
    print -n (escape $png --cols $cols --rows $rows --id $id)
    print ""
}

# The escape sequence that removes an image by id.
export def "delete escape" [--id: int = 1]: nothing -> string {
    let esc = char --integer 27
    let backslash = char --integer 92
    $"($esc)_Ga=d,d=i,i=($id),q=2;($esc)($backslash)"
}

# Remove a previously shown image by id.
export def delete [--id: int = 1]: nothing -> nothing {
    print -n (delete escape --id $id)
}
