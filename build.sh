#!/usr/bin/env bash
#
# Build Flatpak packages into the shared OSTree repository.
#
# Usage:
#   ./build.sh                     # build every package
#   ./build.sh <app-id> [...]      # build selected packages
#   ./build.sh --list              # list available packages
#   ./build.sh --clean             # remove repo/, dist/ and work/
#
# Environment:
#   REPO_DIR   shared OSTree repo (default: ./repo)
#   DIST_DIR   bundle output (default: ./dist)
#   WORK_ROOT  scratch directory (default: ./work)
#   KEEP_REPO=1     add to the existing repo instead of starting clean
#   GPG_SIGN=<key>  sign commits and the repo summary
#   GPG_HOMEDIR     GPG home (default: $HOME/.gnupg)
#   GENERATE_STATIC_DELTAS=0 / PRUNE=0 to disable those steps
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

REPO_DIR="${REPO_DIR:-$ROOT/repo}"
DIST_DIR="${DIST_DIR:-$ROOT/dist}"
WORK_ROOT="${WORK_ROOT:-$ROOT/work}"
KEEP_REPO="${KEEP_REPO:-0}"
GPG_SIGN="${GPG_SIGN:-}"
GPG_HOMEDIR="${GPG_HOMEDIR:-$HOME/.gnupg}"
GENERATE_STATIC_DELTAS="${GENERATE_STATIC_DELTAS:-1}"
PRUNE="${PRUNE:-1}"

export REPO_DIR DIST_DIR WORK_ROOT KEEP_REPO GPG_SIGN GPG_HOMEDIR
export GENERATE_STATIC_DELTAS PRUNE

list_package_envs() {
    find "$ROOT/packages" -mindepth 2 -maxdepth 2 -name package.env -print | sort
}

list_packages() {
    local env
    while IFS= read -r env; do
        (
            # shellcheck disable=SC1090
            . "$env"
            printf '%-28s %-32s %s\n' "$APP_ID" "$APP_NAME" "$VERSION"
        )
    done < <(list_package_envs)
}

die() { echo "error: $*" >&2; exit 1; }

case "${1:-}" in
    --list)
        list_packages
        exit 0
        ;;
    --clean)
        echo "==> Removing $REPO_DIR $DIST_DIR $WORK_ROOT"
        rm -rf "$REPO_DIR" "$DIST_DIR" "$WORK_ROOT"
        exit 0
        ;;
    --help|-h)
        sed -n '2,20p' "$0" | sed 's/^# \{0,1\}//'
        exit 0
        ;;
esac

command -v flatpak >/dev/null || die "flatpak is required"

packages=()
if [ "$#" -eq 0 ]; then
    while IFS= read -r env; do
        packages+=("$(dirname "$env")")
    done < <(list_package_envs)
else
    for arg in "$@"; do
        if [ -f "$arg/package.env" ]; then
            packages+=("$(cd "$arg" && pwd)")
        elif [ -f "$ROOT/packages/$arg/package.env" ]; then
            packages+=("$ROOT/packages/$arg")
        else
            die "unknown package: $arg (try ./build.sh --list)"
        fi
    done
fi

[ "${#packages[@]}" -gt 0 ] || die "no packages found in $ROOT/packages"

if [ "$KEEP_REPO" = "1" ]; then
    mkdir -p "$REPO_DIR"
else
    rm -rf "$REPO_DIR" "$DIST_DIR" "$WORK_ROOT"
    mkdir -p "$REPO_DIR"
fi
mkdir -p "$DIST_DIR" "$WORK_ROOT"

for pkg in "${packages[@]}"; do
    "$ROOT/scripts/build-package.sh" "$pkg"
done

echo
echo "==> Bundles in $DIST_DIR"
ls -lh "$DIST_DIR"/*.flatpak
