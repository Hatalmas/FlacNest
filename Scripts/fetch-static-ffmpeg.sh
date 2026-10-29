#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
DEST="${ROOT}/ThirdParty"
INTEL="${DEST}/ffmpeg-x86_64"
ARM="${DEST}/ffmpeg-arm64"
UNIVERSAL="${DEST}/ffmpeg"

mkdir -p "${DEST}"

download_zip_binary() {
    url="$1"
    dest="$2"
    tmp_zip="$(mktemp -t ffmpeg-static.XXXXXX.zip)"
    tmp_dir="$(mktemp -d -t ffmpeg-static.XXXXXX)"
    curl -fsSL -o "${tmp_zip}" "${url}"
    unzip -o -j "${tmp_zip}" -d "${tmp_dir}" >/dev/null
    found="$(find "${tmp_dir}" -type f -name ffmpeg -print -quit)"
    if [ -z "${found}" ]; then
        found="$(find "${tmp_dir}" -type f -perm -111 -print -quit)"
    fi
    if [ -z "${found}" ]; then
        echo "error: zip from ${url} did not contain an ffmpeg binary" >&2
        rm -rf "${tmp_zip}" "${tmp_dir}"
        return 1
    fi
    cp "${found}" "${dest}"
    chmod +x "${dest}"
    xattr -cr "${dest}" 2>/dev/null || true
    rm -rf "${tmp_zip}" "${tmp_dir}"
}

has_arch() {
    binary="$1"
    arch="$2"
    [ -x "${binary}" ] && lipo -archs "${binary}" 2>/dev/null | grep -qw "${arch}"
}

if ! has_arch "${INTEL}" x86_64 && ! has_arch "${UNIVERSAL}" x86_64; then
    echo "Downloading static Intel ffmpeg (evermeet.cx)…"
    download_zip_binary "https://evermeet.cx/ffmpeg/getrelease/ffmpeg/zip" "${INTEL}"
elif has_arch "${UNIVERSAL}" x86_64 && [ ! -x "${INTEL}" ]; then
    lipo "${UNIVERSAL}" -thin x86_64 -output "${INTEL}" 2>/dev/null || true
fi

if ! has_arch "${ARM}" arm64 && ! has_arch "${UNIVERSAL}" arm64; then
    echo "Downloading static Apple Silicon ffmpeg (ffmpeg.martin-riedl.de)…"
    download_zip_binary "https://ffmpeg.martin-riedl.de/redirect/latest/macos/arm64/release/ffmpeg.zip" "${ARM}"
elif has_arch "${UNIVERSAL}" arm64 && [ ! -x "${ARM}" ]; then
    lipo "${UNIVERSAL}" -thin arm64 -output "${ARM}" 2>/dev/null || true
fi

if [ -x "${INTEL}" ] && [ -x "${ARM}" ]; then
    echo "Creating universal ffmpeg…"
    lipo -create "${INTEL}" "${ARM}" -output "${UNIVERSAL}"
elif [ -x "${ARM}" ]; then
    cp "${ARM}" "${UNIVERSAL}"
elif [ -x "${INTEL}" ]; then
    cp "${INTEL}" "${UNIVERSAL}"
else
    echo "error: could not obtain a static ffmpeg binary" >&2
    exit 1
fi

chmod +x "${UNIVERSAL}"
xattr -cr "${UNIVERSAL}" 2>/dev/null || true

echo "Installed static ffmpeg at ${UNIVERSAL}"
lipo -archs "${UNIVERSAL}"
"${UNIVERSAL}" -hide_banner -version | head -1
