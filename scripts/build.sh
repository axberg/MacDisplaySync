#!/bin/zsh
set -euo pipefail

project_dir=${0:A:h:h}
build_dir="$project_dir/build"
app_dir="$build_dir/MacDisplaySync.app"
contents_dir="$app_dir/Contents"
macos_dir="$contents_dir/MacOS"
resources_dir="$contents_dir/Resources"

mkdir -p "$macos_dir" "$resources_dir"

clang \
  -target arm64-apple-macos13.0 \
  -fmodules \
  -fobjc-arc \
  -Wall \
  -Wextra \
  -framework Foundation \
  -framework IOKit \
  -framework CoreGraphics \
  -F/System/Library/PrivateFrameworks \
  -framework CoreDisplay \
  "$project_dir/Sources/MonitorDDC/main.m" \
  -o "$resources_dir/monitor-ddc"

swiftc \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -framework SwiftUI \
  -framework AppKit \
  "$project_dir"/Sources/MacDisplaySync/*.swift \
  -o "$macos_dir/MacDisplaySync"

swiftc \
  -target arm64-apple-macos13.0 \
  -parse-as-library \
  -swift-version 5 \
  -O \
  -framework Foundation \
  -framework CoreGraphics \
  "$project_dir/Sources/MacDisplaySync/SensorSupport.swift" \
  "$project_dir/Sources/MonitorSensor/main.swift" \
  -o "$resources_dir/monitor-sensor"

cp "$project_dir/Resources/Info.plist" "$contents_dir/Info.plist"
codesign --force --sign - "$resources_dir/monitor-ddc"
codesign --force --sign - "$resources_dir/monitor-sensor"
codesign --force --deep --sign - "$app_dir"

echo "Built $app_dir"
