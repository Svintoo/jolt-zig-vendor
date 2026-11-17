#!/usr/bin/env bash
# Writes the prebuilt library packages of a release into build.zig.zon, between the prebuilt markers.
# Usage: scripts/update_prebuilt.sh <release tag> <directory with joltc-<arch>-<os>-<mode>.tar.gz>
set -euo pipefail
shopt -s nullglob

tag="$1"
assets="$2"
repository="${GITHUB_REPOSITORY:?set GITHUB_REPOSITORY to <owner>/<name>}"

archives=("$assets"/joltc-*.tar.gz)
if [ "${#archives[@]}" -eq 0 ]; then
    echo "no joltc-*.tar.gz in $assets" >&2
    exit 1
fi

block="$(mktemp)"
trap 'rm -f "$block"' EXIT

for archive in "${archives[@]}"; do
    file="$(basename "$archive")"
    stem="${file#joltc-}"
    stem="${stem%.tar.gz}"
    name="prebuilt_${stem//-/_}"
    hash="$(zig fetch "$archive")"
    printf '        .%s = .{\n            .url = "https://github.com/%s/releases/download/%s/%s",\n            .hash = "%s",\n            .lazy = true,\n        },\n' \
        "$name" "$repository" "$tag" "$file" "$hash" >>"$block"
done

awk -v block="$block" '
    /\/\/ prebuilt end/ { while ((getline line < block) > 0) print line; skip = 0 }
    !skip { print }
    /\/\/ prebuilt begin/ { skip = 1 }
' build.zig.zon >build.zig.zon.new
mv build.zig.zon.new build.zig.zon
