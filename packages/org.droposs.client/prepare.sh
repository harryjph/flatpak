#!/usr/bin/env bash
#
# Package-specific preparation hook.
#
# The shared builder calls this with APP_DIR, FILES_DIR (the future /app tree)
# and PACKAGE_WORK_DIR exported, plus everything from package.env.
set -euo pipefail

cd "$APP_DIR"

command -v curl >/dev/null || { echo "curl is required" >&2; exit 1; }
command -v rpm2cpio >/dev/null || { echo "rpm2cpio is required" >&2; exit 1; }
command -v cpio >/dev/null || { echo "cpio is required" >&2; exit 1; }

if [ ! -f "$RPM" ]; then
    echo "Downloading $RPM"
    curl -fL --retry 3 -o "$RPM.part" "$RPM_URL"
    mv "$RPM.part" "$RPM"
fi

echo "Verifying $RPM"
actual="$(sha256sum "$RPM" | cut -d' ' -f1)"
if [ "$actual" != "$RPM_SHA256" ]; then
    echo "error: checksum mismatch for $RPM (got $actual)" >&2
    exit 1
fi

echo "Extracting $RPM"
extract_dir="$PACKAGE_WORK_DIR/extracted"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"
(
    cd "$extract_dir"
    rpm2cpio "$APP_DIR/$RPM" | cpio -idm --quiet
)

install -Dm755 "$extract_dir/usr/bin/drop-app" "$FILES_DIR/bin/drop-app-bin"
install -Dm755 "$APP_DIR/drop-app"              "$FILES_DIR/bin/drop-app"
install -Dm755 "$APP_DIR/umu-run"               "$FILES_DIR/bin/umu-run"

install -Dm644 "$APP_DIR/${APP_ID}.desktop"      "$FILES_DIR/share/applications/${APP_ID}.desktop"
install -Dm644 "$APP_DIR/${APP_ID}.metainfo.xml" "$FILES_DIR/share/metainfo/${APP_ID}.metainfo.xml"

install -Dm644 "$extract_dir/usr/share/icons/hicolor/32x32/apps/drop-app.png" \
    "$FILES_DIR/share/icons/hicolor/32x32/apps/${APP_ID}.png"
install -Dm644 "$extract_dir/usr/share/icons/hicolor/128x128/apps/drop-app.png" \
    "$FILES_DIR/share/icons/hicolor/128x128/apps/${APP_ID}.png"
install -Dm644 "$extract_dir/usr/share/icons/hicolor/256x256@2/apps/drop-app.png" \
    "$FILES_DIR/share/icons/hicolor/256x256/apps/${APP_ID}.png"
