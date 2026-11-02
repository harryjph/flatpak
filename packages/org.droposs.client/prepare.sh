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
payload="$PACKAGE_WORK_DIR/payload.cpio"
rm -rf "$extract_dir"
mkdir -p "$extract_dir"

# Ubuntu's rpm2cpio (rpm 4.18) exits non-zero for RPMs produced by newer rpm
# versions even when it writes a complete payload. Judge success by whether a
# non-empty cpio archive was produced, and let cpio validate it.
set +e
rpm2cpio "$APP_DIR/$RPM" > "$payload"
rpm2cpio_rc=$?
set -e
if [ "$rpm2cpio_rc" -ne 0 ]; then
    echo "warning: rpm2cpio exited $rpm2cpio_rc (continuing if the payload is valid)"
fi
if [ ! -s "$payload" ]; then
    echo "error: rpm2cpio produced no payload for $RPM" >&2
    exit 1
fi

(
    cd "$extract_dir"
    cpio -idm < "$payload"
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
