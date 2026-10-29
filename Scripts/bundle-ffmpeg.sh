#!/bin/sh
set -eu

if [ -z "${BUILT_PRODUCTS_DIR:-}" ] || [ -z "${UNLOCALIZED_RESOURCES_FOLDER_PATH:-}" ]; then
    echo "warning: bundle-ffmpeg.sh must run from an Xcode build phase"
    exit 0
fi

DEST="${BUILT_PRODUCTS_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/bin"
LIB_DEST="${DEST}/lib"
STATIC="${SRCROOT}/ThirdParty/ffmpeg"

mkdir -p "${DEST}"
rm -rf "${LIB_DEST}"

bundle_static() {
    cp "${STATIC}" "${DEST}/ffmpeg"
    chmod 755 "${DEST}/ffmpeg"
    xattr -cr "${DEST}/ffmpeg" 2>/dev/null || true
    echo "Bundled static ffmpeg from ThirdParty/ffmpeg"
}

bundle_homebrew_with_dylibbundler() {
    FFMPEG="$(command -v ffmpeg || true)"
    if [ ! -x "${FFMPEG}" ]; then
        return 1
    fi

    cp "${FFMPEG}" "${DEST}/ffmpeg"
    chmod 755 "${DEST}/ffmpeg"
    mkdir -p "${LIB_DEST}"

    dylibbundler -of -b -x "${DEST}/ffmpeg" -d "${LIB_DEST}" -p @executable_path/lib \
        -s /opt/homebrew/lib/ \
        -s /opt/homebrew/opt/ \
        -s /opt/homebrew/Cellar/ \
        -s /usr/local/lib/ \
        -s /usr/local/opt/ \
        -s /usr/local/Cellar/

    xattr -cr "${DEST}" 2>/dev/null || true
    echo "Bundled Homebrew ffmpeg with dylibbundler"
}

needed_archs="${ARCHS:-$(uname -m)}"
static_archs=""
if [ -x "${STATIC}" ]; then
    static_archs="$(lipo -archs "${STATIC}" 2>/dev/null || true)"
fi

static_covers_needed=1
for arch in ${needed_archs}; do
    case "${arch}" in
        arm64|x86_64)
            if ! echo " ${static_archs} " | grep -q " ${arch} "; then
                static_covers_needed=0
            fi
            ;;
    esac
done

if [ -x "${STATIC}" ] && [ "${static_covers_needed}" -eq 1 ]; then
    bundle_static
    exit 0
fi

if [ -x "${STATIC}" ] && [ "${static_covers_needed}" -eq 0 ]; then
    echo "warning: ThirdParty/ffmpeg ($(echo "${static_archs}" | tr ' ' ',')) is missing archs required for this build (${needed_archs}). Trying Homebrew ffmpeg."
fi

if command -v dylibbundler >/dev/null 2>&1 && bundle_homebrew_with_dylibbundler; then
    exit 0
fi

cat <<EOF
warning: No bundled ffmpeg was created for FlacNest.

Recommended (single static binary, works in App Sandbox):
  ./Scripts/fetch-static-ffmpeg.sh
  Then rebuild FlacNest.

Alternative (bundle your Homebrew ffmpeg + dylibs):
  brew install dylibbundler
  Then rebuild FlacNest.

Until then, Prepare Export falls back to a system ffmpeg path if one exists.
EOF
