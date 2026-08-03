#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/ThirdParty"
BINARY="${DEST}/ffmpeg"
TMP_ZIP="$(mktemp -t ffmpeg-static.XXXXXX.zip)"

mkdir -p "${DEST}"

if [ -x "${BINARY}" ]; then
    echo "Static ffmpeg already present at ${BINARY}"
    otool -L "${BINARY}" | head -5
    exit 0
fi

echo "Downloading static ffmpeg for macOS (evermeet.cx)…"
curl -fsSL -o "${TMP_ZIP}" "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip"
unzip -o -j "${TMP_ZIP}" ffmpeg -d "${DEST}"
chmod +x "${BINARY}"
xattr -cr "${BINARY}" 2>/dev/null || true
rm -f "${TMP_ZIP}"

echo "Installed static ffmpeg at ${BINARY}"
"${BINARY}" -version | head -1
