# Harryjph's Flatpak repository

A personal Flatpak remote that can host any number of packages, built from
upstream releases and served from GitHub Pages.

Current packages:

| App ID | Package | Version |
| --- | --- | --- |
| `org.droposs.client` | [Drop Desktop Client](packages/org.droposs.client/README.md) | 0.4.0 |

## Install from the published remote

```sh
flatpak remote-add --if-not-exists --user harryjph \
  https://harryjph.github.io/flatpak/harryjph.flatpakrepo

flatpak install --user harryjph org.droposs.client
flatpak update --user
```

While the repository is unsigned, add it with `--no-gpg-verify` instead; see
[Publishing](#publishing-to-github-pages) for enabling signing.

## Build locally

Requirements: `flatpak`, `curl`, `rpm2cpio` (from the `rpm` package on Ubuntu),
`cpio` and `sha256sum`. `flatpak-builder` and the GNOME SDK are **not**
required for prebuilt packages.

```sh
./build.sh                       # build every package
./build.sh org.droposs.client    # build one package
./build.sh --list                # list packages
./build.sh --clean               # remove repo/, dist/ and work/
```

Outputs:

```
repo/                            shared OSTree repository
dist/<app-id>.flatpak            per-package single-file bundle
work/<app-id>/                   extracted/finalized app tree
```

By default a build starts with a clean repository. To add to an existing repo
(for publishing), use:

| Variable | Meaning |
| --- | --- |
| `KEEP_REPO=1` | Append to the existing repo instead of deleting it |
| `REPO_DIR=path` | Repository location (default `repo/`) |
| `DIST_DIR=path` | Bundle output (default `dist/`) |
| `WORK_ROOT=path` | Scratch directory (default `work/`) |
| `GPG_SIGN=<key-id>` | Sign commits and the repository summary |
| `GPG_HOMEDIR=<dir>` | GPG home (default `$HOME/.gnupg`) |
| `GENERATE_STATIC_DELTAS=0` | Disable static deltas |
| `PRUNE=0` | Disable pruning unreachable objects |

```sh
KEEP_REPO=1 GPG_SIGN=ABCD1234... ./build.sh
```

Install a local bundle:

```sh
flatpak install --user ./dist/org.droposs.client.flatpak
```

The Drop package needs `org.gnome.Platform//50`; add Flathub first if needed.

## Adding a package

Create `packages/<app-id>/` containing:

```
package.env       app metadata and source information
prepare.sh        populates $FILES_DIR with the /app tree
finish-args.txt   one `flatpak build-finish` permission per line
README.md         package-specific notes
...               desktop files, icons, wrappers, etc.
```

`package.env` is sourced by the builder. Required keys:

```sh
APP_ID=com.example.App
APP_NAME="Example App"
VERSION=1.2.3
RUNTIME=org.gnome.Platform
RUNTIME_VERSION=50
COMMAND=example-app

# Optional
BRANCH=stable                    # default: stable
ARCH=x86_64                      # default: x86_64
SDK=org.gnome.Sdk                # omitted from metadata if empty
RUNTIME_REPO=https://dl.flathub.org/repo/flathub.flatpakrepo
```

Any additional keys (source URL, checksum, etc.) are exported to
`prepare.sh`.

`prepare.sh` runs with these variables exported:

* `APP_DIR` — the package directory
* `FILES_DIR` — populate this as the future `/app` tree
* `PACKAGE_WORK_DIR` — scratch space for downloads/extraction
* everything from `package.env`

Example:

```sh
#!/usr/bin/env bash
set -euo pipefail
curl -fL -o "$PACKAGE_WORK_DIR/app.tar.gz" "$SOURCE_URL"
tar -xf "$PACKAGE_WORK_DIR/app.tar.gz" -C "$PACKAGE_WORK_DIR"
install -Dm755 "$PACKAGE_WORK_DIR/app/example-app" "$FILES_DIR/bin/example-app"
install -Dm644 "$APP_DIR/example.desktop" "$FILES_DIR/share/applications/$APP_ID.desktop"
```

Then:

```sh
./build.sh <app-id>
```

The GitHub Actions workflow discovers packages automatically from
`packages/*/package.env`; no workflow edit is needed. Use `--list` to see the
package table.

## Publishing to GitHub Pages

`.github/workflows/pages.yml` builds every package, appends it to the
persistent OSTree repo on the `gh-pages` branch, signs commits and the summary
(when a key is configured), generates one shared `.flatpakrepo`, and publishes
an index. One remote serves all packages.

One-time setup:

1. Create a dedicated passphrase-less signing key:

   ```sh
   gpg --batch --pinentry-mode loopback --passphrase '' \
       --quick-generate-key "Flatpak Signing <flatpak@example.org>" ed25519 sign 0
   gpg --armor --export-secret-keys flatpak@example.org
   ```

2. Add repository secret `FLATPAK_GPG_PRIVATE_KEY` with the ASCII-armored
   private key. Optionally add variable `FLATPAK_GPG_KEY_ID`.

3. Run the **Publish Flatpak repository** workflow (or push a `v*` tag). The
   first run creates `gh-pages`.

4. In **Settings → Pages**, choose **Deploy from a branch**, branch `gh-pages`,
   folder `/ (root)`.

Published layout:

```
gh-pages/
  .nojekyll
  index.html
  harryjph.flatpakrepo        <- one remote for every package
  bundles/<app-id>.flatpak
  repo/                       <- OSTree repository
```

The remote name, title and homepage are configured in `repo.conf`.

GitHub Pages limits: ~1 GB published site, 100 MB per file, ~100 GB/month
bandwidth (soft), 10 builds/hour. The repo grows with each release; prune old
history or rebuild periodically. See `AGENTS.md` for maintenance details.

## Layout

```
build.sh                     build dispatcher
repo.conf                    remote name/title/homepage
scripts/build-package.sh     generic package builder
scripts/write-flatpakrepo.sh .flatpakrepo generator
packages/<app-id>/           one directory per package
.github/workflows/pages.yml  build + sign + deploy
repo/                        generated OSTree repository
dist/                        generated bundles
work/                        generated build trees
AGENTS.md                    decisions, gotchas and testing guide
```
