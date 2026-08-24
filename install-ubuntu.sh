#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
launcher="$script_dir/bin/preview"
stage_launcher="$script_dir/bin/stage"
destination_dir="${HOME}/.local/bin"
destination="$destination_dir/preview"
stage_destination="$destination_dir/stage"

mkdir -p "$destination_dir"
chmod +x "$launcher"
chmod +x "$stage_launcher"

if [ -e "$destination" ] && [ ! -L "$destination" ]; then
    echo "preview: $destination exists and is not a symbolic link" >&2
    exit 1
fi
if [ -e "$stage_destination" ] && [ ! -L "$stage_destination" ]; then
    echo "preview: $stage_destination exists and is not a symbolic link" >&2
    exit 1
fi

ln -sfn "$launcher" "$destination"
ln -sfn "$stage_launcher" "$stage_destination"
echo "Installed preview at $destination"
echo "Installed stage at $stage_destination"
