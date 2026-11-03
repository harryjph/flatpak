#!/usr/bin/env bash
#
# Package-specific preparation hook.
#
# Hoard is installed from its released .deb, the same binary-extraction recipe
# upstream uses for its own Flatpak manifest: the bundle carries hoard-desktop,
# the hoardd service and the hoard CLI, so nothing is rebuilt here.
set -euo pipefail

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v ar >/dev/null || { echo "ar (binutils) is required" >&2; exit 1; }
command -v tar >/dev/null || { echo "tar is required" >&2; exit 1; }

deb="$PACKAGE_WORK_DIR/$DEB"
if [ ! -f "$deb" ]; then
    echo "Downloading $DEB"
    curl -fL --retry 3 -o "$deb.part" "$DEB_URL"
    mv "$deb.part" "$deb"
fi

echo "Verifying $DEB"
actual="$(sha256sum "$deb" | cut -d' ' -f1)"
if [ "$actual" != "$DEB_SHA256" ]; then
    echo "error: checksum mismatch for $DEB (got $actual)" >&2
    exit 1
fi

echo "Extracting $DEB"
extract_dir="$PACKAGE_WORK_DIR/deb"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
(
    cd "$extract_dir"
    ar x "$deb"
    tar -xf data.tar.*
)

# hoard-desktop spawns hoardd as a bare-named sibling of the running binary,
# and the CLI is a client of the same daemon, so all three go in /app/bin.
for bin in hoard-desktop hoardd hoard; do
    install -Dm755 "$extract_dir/usr/bin/$bin" "$FILES_DIR/bin/$bin"
done

install -Dm644 "$APP_DIR/${APP_ID}.desktop" \
    "$FILES_DIR/share/applications/${APP_ID}.desktop"
install -Dm644 "$APP_DIR/${APP_ID}.metainfo.xml" \
    "$FILES_DIR/share/metainfo/${APP_ID}.metainfo.xml"

# Rename the icons to the Flatpak ID so the icon theme resolves Icon=.
install -Dm644 "$extract_dir/usr/share/icons/hicolor/32x32/apps/hoard-desktop.png" \
    "$FILES_DIR/share/icons/hicolor/32x32/apps/${APP_ID}.png"
install -Dm644 "$extract_dir/usr/share/icons/hicolor/128x128/apps/hoard-desktop.png" \
    "$FILES_DIR/share/icons/hicolor/128x128/apps/${APP_ID}.png"
install -Dm644 "$extract_dir/usr/share/icons/hicolor/256x256@2/apps/hoard-desktop.png" \
    "$FILES_DIR/share/icons/hicolor/256x256/apps/${APP_ID}.png"
install -Dm644 "$extract_dir/usr/share/icons/hicolor/512x512/apps/hoard-desktop.png" \
    "$FILES_DIR/share/icons/hicolor/512x512/apps/${APP_ID}.png"
