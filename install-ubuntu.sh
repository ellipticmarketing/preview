#!/usr/bin/env sh
set -eu

script_dir=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
launcher="$script_dir/bin/preview"
destination_dir="${HOME}/.local/bin"
destination="$destination_dir/preview"

mkdir -p "$destination_dir"
chmod +x "$launcher"

if [ -e "$destination" ] && [ ! -L "$destination" ]; then
    echo "preview: $destination exists and is not a symbolic link" >&2
    exit 1
fi

ln -sfn "$launcher" "$destination"
echo "Installed preview at $destination"
