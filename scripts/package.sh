#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
app_dir="$project_dir/build/MacDisplaySync.app"
dist_dir="$project_dir/dist"

if [[ ! -d "$app_dir" ]]; then
  "$project_dir/scripts/build.sh"
fi

version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' \
  "$app_dir/Contents/Info.plist")
archive="$dist_dir/MacDisplaySync-$version-macos-arm64.zip"

mkdir -p "$dist_dir"
rm -f "$archive"
ditto -c -k --norsrc --keepParent "$app_dir" "$archive"

echo "Packaged $archive"
