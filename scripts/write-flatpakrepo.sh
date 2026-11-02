#!/usr/bin/env bash
#
# Write a .flatpakrepo descriptor for a published OSTree repository.
#
# Usage:
#   scripts/write-flatpakrepo.sh OUTPUT URL [GPG_KEY_ID]
#
# URL must point at the directory that contains the OSTree summary (usually
# https://<owner>.github.io/<repo>/repo/). If GPG_KEY_ID is given, the public
# key is embedded as base64 in GPGKey=; otherwise the descriptor describes an
# unsigned repository and clients must use --no-gpg-verify.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
if [ -f "$ROOT/repo.conf" ]; then
    # shellcheck disable=SC1091
    . "$ROOT/repo.conf"
fi

output="${1:?usage: $0 OUTPUT URL [GPG_KEY_ID]}"
url="${2:?usage: $0 OUTPUT URL [GPG_KEY_ID]}"
key_id="${3:-}"

case "$url" in
    */) ;;
    *) url="${url}/" ;;
esac

if [ -n "${GPG_HOMEDIR:-}" ] && [ -z "${GNUPGHOME:-}" ]; then
    export GNUPGHOME="$GPG_HOMEDIR"
fi

title="${REPO_TITLE:-Flatpak Repository}"
homepage="${REPO_HOMEPAGE:-}"
comment="${REPO_COMMENT:-Flatpak packages}"
description="${REPO_DESCRIPTION:-A personal Flatpak repository.}"

mkdir -p "$(dirname "$output")"
tmp="$(mktemp "${output}.XXXXXX")"
trap 'rm -f "$tmp"' EXIT

{
    echo "[Flatpak Repo]"
    echo "Title=${title}"
    echo "Url=${url}"
    [ -n "$homepage" ] && echo "Homepage=${homepage}"
    echo "Comment=${comment}"
    echo "Description=${description}"
    if [ -n "$key_id" ]; then
        command -v gpg >/dev/null || {
            echo "error: gpg is required to embed the signing key" >&2
            exit 1
        }
        key_b64="$(gpg --export "$key_id" | base64 | tr -d '\n')"
        if [ -z "$key_b64" ]; then
            echo "error: gpg exported an empty key for $key_id" >&2
            exit 1
        fi
        echo "GPGKey=${key_b64}"
    fi
} > "$tmp"

mv "$tmp" "$output"
trap - EXIT
echo "Wrote $output"
