#!/bin/zsh
set -euo pipefail

script_dir="$(cd "$(dirname "$0")" && pwd)"
asset_dir="$script_dir/../../public/demos"
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/errol-short-demo.XXXXXX")"
export ERROL_DEMO_OUTPUT="$build_dir"

swiftc -module-cache-path "$build_dir/swift-cache" "$script_dir/render.swift" -o "$build_dir/render" -framework AppKit
"$build_dir/render"
ffmpeg -hide_banner -loglevel warning -y -framerate 30 -i "$build_dir/frames/frame-%04d.png" -c:v libx264 -preset slow -crf 18 -pix_fmt yuv420p -movflags +faststart -an -color_primaries bt709 -color_trc bt709 -colorspace bt709 "$build_dir/errol-quick-demo.mp4"
ffprobe -v error -show_entries format=duration,size:stream=codec_name,profile,pix_fmt,width,height,r_frame_rate,nb_frames -of json "$build_dir/errol-quick-demo.mp4"

mkdir -p "$asset_dir"
cp "$build_dir/errol-quick-demo.mp4" "$asset_dir/errol-quick-demo.mp4"
cp "$build_dir/two-flights.png" "$asset_dir/errol-quick-demo-poster.png"
print "Updated the short demo in $asset_dir"
print "Rendered frames and build files: $build_dir"
