#!/usr/bin/env bash
#
# Build one package into the shared Flatpak OSTree repository.
#
# Usage:
#   scripts/build-package.sh packages/<app-id>
#   scripts/build-package.sh <app-id>
#
# The package directory must contain package.env, prepare.sh and optionally
# finish-args.txt. prepare.sh must populate $FILES_DIR with the /app tree.
#
# Environment:
#   REPO_DIR      shared OSTree repo (default: <root>/repo)
#   DIST_DIR      bundle output (default: <root>/dist)
#   WORK_ROOT     scratch directory (default: <root>/work)
#   GPG_SIGN      optional GPG key ID for signing commits + summary
#   GPG_HOMEDIR   GPG home (default: $HOME/.gnupg)
#   GENERATE_STATIC_DELTAS=0 / PRUNE=0 to disable those steps
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ARG="${1:?usage: $0 PACKAGE}"

if [ -d "$ARG" ] && [ -f "$ARG/package.env" ]; then
    PKG_DIR="$(cd "$ARG" && pwd)"
else
    PKG_DIR="$ROOT/packages/${ARG%/}"
fi

[ -f "$PKG_DIR/package.env" ] || {
    echo "error: $PKG_DIR/package.env not found" >&2
    exit 1
}
[ -x "$PKG_DIR/prepare.sh" ] || {
    echo "error: $PKG_DIR/prepare.sh is missing or not executable" >&2
    exit 1
}

REPO_DIR="${REPO_DIR:-$ROOT/repo}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
WORK_ROOT="${WORK_ROOT:-$ROOT/work}"
GENERATE_STATIC_DELTAS="${GENERATE_STATIC_DELTAS:-1}"
PRUNE="${PRUNE:-1}"
GPG_HOMEDIR="${GPG_HOMEDIR:-$HOME/.gnupg}"

# Export package.env values so prepare.sh can use them too.
set -a
# shellcheck disable=SC1091
. "$PKG_DIR/package.env"
set +a

: "${APP_ID:?APP_ID missing from package.env}"
: "${APP_NAME:?APP_NAME missing from package.env}"
: "${VERSION:?VERSION missing from package.env}"
: "${RUNTIME:?RUNTIME missing from package.env}"
: "${RUNTIME_VERSION:?RUNTIME_VERSION missing from package.env}"

ARCH="${ARCH:-x86_64}"
BRANCH="${BRANCH:-stable}"
SDK="${SDK:-}"
RUNTIME_REPO="${RUNTIME_REPO:-https://dl.flathub.org/repo/flathub.flatpakrepo}"

PACKAGE_WORK_DIR="$WORK_ROOT/$APP_ID"
FILES_DIR="$PACKAGE_WORK_DIR/files"

echo "==> $APP_NAME $VERSION ($APP_ID)"
rm -rf "$PACKAGE_WORK_DIR"
mkdir -p "$FILES_DIR"

export APP_DIR="$PKG_DIR"
export FILES_DIR
export PACKAGE_WORK_DIR

"$PKG_DIR/prepare.sh"

if [ -z "$(find "$FILES_DIR" -mindepth 1 -print -quit)" ]; then
    echo "error: prepare.sh produced no files in $FILES_DIR" >&2
    exit 1
fi

COMMAND="${COMMAND:-}"
if [ -z "$COMMAND" ]; then
    COMMAND="$(find "$FILES_DIR/bin" -maxdepth 1 -type f -perm -u+x -printf '%f\n' 2>/dev/null | head -n 1)"
fi
[ -n "$COMMAND" ] || {
    echo "error: no COMMAND set and no executable found in $FILES_DIR/bin" >&2
    exit 1
}

{
    echo "[Application]"
    echo "name=${APP_ID}"
    echo "runtime=${RUNTIME}/${ARCH}/${RUNTIME_VERSION}"
    [ -n "$SDK" ] && echo "sdk=${SDK}/${ARCH}/${RUNTIME_VERSION}"
    echo "command=${COMMAND}"
} > "$PACKAGE_WORK_DIR/metadata"

finish_args=()
if [ -f "$PKG_DIR/finish-args.txt" ]; then
    while IFS= read -r arg; do
        arg="${arg%$'\r'}"
        case "$arg" in
            ""|\#*) continue ;;
        esac
        finish_args+=("$arg")
    done < "$PKG_DIR/finish-args.txt"
fi

echo "==> Finalizing metadata"
flatpak build-finish --command="$COMMAND" "${finish_args[@]}" "$PACKAGE_WORK_DIR"

export_args=(--arch="$ARCH" --subject="${APP_NAME} ${VERSION}")
update_args=()
if [ -n "${GPG_SIGN:-}" ]; then
    echo "==> Signing with $GPG_SIGN"
    export_args+=(--gpg-sign="$GPG_SIGN" --gpg-homedir="$GPG_HOMEDIR")
    update_args+=(--gpg-sign="$GPG_SIGN" --gpg-homedir="$GPG_HOMEDIR")
fi

mkdir -p "$REPO_DIR"
echo "==> Exporting to $REPO_DIR"
flatpak build-export "${export_args[@]}" "$REPO_DIR" "$PACKAGE_WORK_DIR" "$BRANCH"

[ "$GENERATE_STATIC_DELTAS" = "1" ] && update_args+=(--generate-static-deltas)
[ "$PRUNE" = "1" ] && update_args+=(--prune)
if [ "${#update_args[@]}" -gt 0 ]; then
    echo "==> Updating repository metadata"
    flatpak build-update-repo "${update_args[@]}" "$REPO_DIR"
fi

mkdir -p "$DIST_DIR"
echo "==> Creating $DIST_DIR/$APP_ID.flatpak"
rm -f "$DIST_DIR/$APP_ID.flatpak"
flatpak build-bundle \
    --arch="$ARCH" \
    --runtime-repo="$RUNTIME_REPO" \
    "$REPO_DIR" "$DIST_DIR/$APP_ID.flatpak" "$APP_ID" "$BRANCH"

echo "==> Built $APP_ID $VERSION"
