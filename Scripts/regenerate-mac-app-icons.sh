#!/bin/bash
set -euo pipefail

ICONSET="$(cd "$(dirname "$0")/.." && pwd)/FlacNest/Assets.xcassets/AppIcon.appiconset"
MASTER="$(mktemp -t iconflac-master.XXXXXX.png)"
trap 'rm -f "$MASTER"' EXIT

if [[ ! -f "$ICONSET/iconflac.png" ]]; then
  echo "Missing source: $ICONSET/iconflac.png" >&2
  exit 1
fi

cp "$ICONSET/iconflac.png" "$MASTER"

resize() {
  local out="$1"
  local px="$2"
  sips -z "$px" "$px" "$MASTER" --out "$out" >/dev/null
  echo "Wrote $out (${px}x${px})"
}

resize "$ICONSET/16.png" 16
resize "$ICONSET/32.png" 32
resize "$ICONSET/32 2.png" 32
resize "$ICONSET/64.png" 64
resize "$ICONSET/128.png" 128
resize "$ICONSET/256.png" 256
resize "$ICONSET/256 1.png" 256
resize "$ICONSET/iconflac 1.png" 512
resize "$ICONSET/iconflac.png" 512
resize "$ICONSET/1024.png" 1024

echo "Done. All AppIcon sizes regenerated from iconflac.png (master copied before resize)."
