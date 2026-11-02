# AGENTS.md — Harryjph's Flatpak repository

This repository hosts any number of Flatpak packages and publishes them as one
signed OSTree remote on GitHub Pages. Read this before changing the build
system, permissions or launcher wrappers.

* Remote: `https://harryjph.github.io/flatpak/harryjph.flatpakrepo`
* Remote name: `harryjph`
* Source: `https://github.com/harryjph/flatpak`
* Default branch: `main`; published site branch: `gh-pages`

## Repository structure

```
build.sh                     build dispatcher
repo.conf                    remote name/title/homepage
scripts/build-package.sh     generic package builder
scripts/write-flatpakrepo.sh .flatpakrepo generator
packages/<app-id>/           one directory per package
  package.env                metadata + source info (sourced by the builder)
  prepare.sh                 populates $FILES_DIR with the /app tree
  finish-args.txt            one flatpak build-finish argument per line
  README.md                  package notes
  ...                        desktop files, icons, wrappers, patches, etc.
.github/workflows/pages.yml  build + sign + deploy all packages
repo/                        generated OSTree repo (shared by all packages)
dist/                        generated per-package bundles
work/                        generated per-package build trees
```

Generated directories are gitignored. `.flatpak-data/` is a project-local test
installation used in the dev container and is also ignored.

## Build system

`./build.sh` is the entrypoint:

```sh
./build.sh                       # build every package
./build.sh <app-id> [...]        # build selected packages
./build.sh --list                # list packages
./build.sh --clean               # remove repo/, dist/ and work/
```

`build.sh` removes `repo/` first unless `KEEP_REPO=1`, then calls
`scripts/build-package.sh` for each package. Each package is exported into the
same OSTree repo and gets its own bundle at `dist/<app-id>.flatpak`.

Environment:

| Variable | Default | Meaning |
| --- | --- | --- |
| `REPO_DIR` | `./repo` | Shared OSTree repository |
| `DIST_DIR` | `./dist` | Bundle output |
| `WORK_ROOT` | `./work` | Scratch directory |
| `KEEP_REPO` | `0` | `1` = append to the existing repo |
| `GPG_SIGN` | empty | GPG key ID for commits + summary |
| `GPG_HOMEDIR` | `$HOME/.gnupg` | GPG home |
| `GENERATE_STATIC_DELTAS` | `1` | Generate static deltas |
| `PRUNE` | `1` | Prune unreachable repo objects |

`build-package.sh` always appends; only the root dispatcher clears the repo.
This makes building N packages into one repo predictable.

### package.env

Required keys:

```sh
APP_ID=org.example.App
APP_NAME="Example App"
VERSION=1.2.3
RUNTIME=org.gnome.Platform
RUNTIME_VERSION=50
COMMAND=example-app
```

Optional keys:

```sh
BRANCH=stable                    # default: stable
ARCH=x86_64                      # default: x86_64
SDK=org.gnome.Sdk                # omitted from metadata if empty
RUNTIME_REPO=https://dl.flathub.org/repo/flathub.flatpakrepo
```

Any other keys are exported to `prepare.sh` (source URLs, checksums, etc.).
The builder generates the metadata file:

```ini
[Application]
name=$APP_ID
runtime=$RUNTIME/$ARCH/$RUNTIME_VERSION
sdk=$SDK/$ARCH/$RUNTIME_VERSION
command=$COMMAND
```

and then runs `flatpak build-finish` with the lines from `finish-args.txt`
(blank lines and `#` comments ignored).

### prepare.sh contract

Executable `prepare.sh` runs with:

* `APP_DIR` — absolute package directory
* `FILES_DIR` — populate this as the future `/app` tree
* `PACKAGE_WORK_DIR` — scratch space for downloads/extraction
* all `package.env` variables exported

It must install the app under `$FILES_DIR` (usually `bin/`, `share/applications`,
`share/icons/hicolor/...`, `share/metainfo`). The builder checks that
`$FILES_DIR` is non-empty and installs `COMMAND` from `$FILES_DIR/bin` if it
can find an executable.

### Adding a package

1. Create `packages/<app-id>/`.
2. Add `package.env`, `prepare.sh` (chmod +x), `finish-args.txt`, `README.md`.
3. Add desktop file, AppStream metainfo and icons with names matching
   `$APP_ID` (`$APP_ID.desktop`, `$APP_ID.metainfo.xml`, `$APP_ID.png`).
4. Run `./build.sh <app-id>` and install the bundle.
5. Run the package-specific checks (see Testing).
6. Commit. The Pages workflow discovers `packages/*/package.env` automatically;
   no workflow edit is needed.
7. New packages use the same `harryjph` remote automatically.

## Publishing to GitHub Pages

GitHub Pages is only available for **public** repositories on the free plan.
Private repositories require a paid plan with Pages support. If the repository
must stay private, publish `dist/*.flatpak` as GitHub Release assets instead;
the workflow's `gh-pages` repo is still built but cannot be served.

One OSTree repo serves every package. The workflow:

1. Checks out `gh-pages` into `site/` (preserving repo history).
2. Imports the signing key from `FLATPAK_GPG_PRIVATE_KEY`.
3. Runs `./build.sh` with `REPO_DIR=site/repo`, `DIST_DIR=site/bundles`,
   `KEEP_REPO=1` and `GPG_SIGN` set.
4. Writes `site/harryjph.flatpakrepo` with the embedded public key.
5. Generates `site/index.html` listing packages.
6. Commits and pushes `gh-pages`.

Published layout:

```
gh-pages/
  .nojekyll
  index.html
  harryjph.flatpakrepo
  bundles/<app-id>.flatpak
  repo/                       # OSTree repository
```

### One-time setup

```sh
gpg --batch --pinentry-mode loopback --passphrase '' \
    --quick-generate-key "Flatpak Signing <flatpak@example.org>" ed25519 sign 0
gpg --armor --export-secret-keys flatpak@example.org
```

* Add repository secret `FLATPAK_GPG_PRIVATE_KEY` with the ASCII-armored
  private key.
* Optionally add repository variable `FLATPAK_GPG_KEY_ID` if the keyring has
  more than one secret key; otherwise the workflow picks the first `sec:` key.
* Settings → Pages → **Deploy from a branch** → `gh-pages` → `/ (root)`.
* Do not protect `gh-pages` against pushes from Actions.

The key must be passphrase-less; CI cannot answer a pinentry prompt. Keep the
same key across releases, otherwise clients that trusted the old key may fail
to verify update history. If the secret is not configured the workflow still
deploys, but the repo is unsigned and `GPGKey` is omitted; clients then need
`--no-gpg-verify`. The official remote should always be signed.

This repository's live signing key is:

```
fingerprint BFCA9A6542FFA510BDF73C0CA8D6C76ED26393C7
public key  keys/harryjph-flatpak.asc
```

The private key exists only as the `FLATPAK_GPG_PRIVATE_KEY` Actions secret
(GitHub secrets are write-only, so there is no local copy). To rotate, generate
a new key, update the secret and `keys/*.asc`, remove `site/repo` for the first
signed publish, and tell users to re-add the remote if verification fails.

GitHub Pages for private repositories requires a paid plan; this repository is
public so the free Pages tier works.

If a repository was previously published unsigned, remove `site/repo` before
the first signed publish (or start from a fresh `gh-pages` branch) so the whole
history is signed with the final key.

`scripts/write-flatpakrepo.sh` embeds the public key as base64:

```ini
[Flatpak Repo]
Title=...
Url=https://harryjph.github.io/flatpak/repo/
Homepage=https://github.com/harryjph/flatpak
Comment=...
Description=...
GPGKey=<base64>
```

Remote metadata lives in `repo.conf` (`REMOTE_NAME`, `REPO_TITLE`,
`REPO_HOMEPAGE`, `REPO_COMMENT`, `REPO_DESCRIPTION`).

### Client usage

```sh
flatpak remote-add --if-not-exists --user harryjph \
  https://harryjph.github.io/flatpak/harryjph.flatpakrepo
flatpak install --user harryjph <app-id>
flatpak update --user
```

Direct bundles are at
`https://harryjph.github.io/flatpak/bundles/<app-id>.flatpak`.

### GitHub Pages limits and maintenance

~1 GB published site, 100 MB per file, ~100 GB/month bandwidth (soft),
10 builds/hour. Each app release adds objects plus a static delta (Drop is
~13 MB per delta). `build-update-repo --prune` removes unreachable objects but
reachable history still grows. Periodically rebuild `site/repo` from the
latest releases or prune old history; clients do a full download for that
release. Use a CDN/object store for a large audience.

All runtimes are installed from Flathub in the workflow. A package using a
different runtime repo must have it added to the workflow's runtime step.

## Package: org.droposs.client (Drop Desktop Client)

Upstream:

```
https://github.com/Drop-OSS/drop/releases/download/v0.4.0-rc-6/Drop.Desktop.Client-0.4.0-1.x86_64.rpm
sha256 1636f5906bdd3ef19a410a88c5e4d976bd05de26e00b7895ae1f1b35c86d9fe8
version 0.4.0 (rc-6), x86_64
```

Drop is a Tauri v2 / WebKitGTK 4.1 client. The RPM contains a prebuilt binary,
a desktop file and icons. No compilation is involved.

### Runtime choice

`org.gnome.Platform//50` must provide:

* `libwebkit2gtk-4.1.so.0` (not only 6.0)
* ICU 77 (`libicu*.so.77`)
* glycin, GTK 3
* glibc >= 2.42 (the Fedora 44 build requires 2.42)

Run `flatpak run --command=ldd org.droposs.client /app/bin/drop-app-bin` after
changing the runtime. If a future GNOME runtime drops WebKitGTK 4.1, stay on
the last branch that has it, switch runtimes, or bundle WebKitGTK (large and
fragile).

### Permissions (finish-args.txt)

```
--share=network
--share=ipc
--socket=x11
--socket=wayland
--socket=pulseaudio
--device=all
--filesystem=host
--talk-name=org.freedesktop.Flatpak
--talk-name=org.freedesktop.Notifications
--talk-name=org.kde.StatusNotifierWatcher
--own-name=org.droposs.client.SingleInstance
```

Rationale:

* `--filesystem=host`: games may be installed anywhere; cloud saves and Proton
  paths are outside the app home; game dirs must stay usable outside the
  sandbox.
* `--device=all`: GPU, controllers/gamepads and other devices.
* `--talk-name=org.freedesktop.Flatpak`: required for `flatpak-spawn --host`.
  This effectively permits arbitrary host command execution, which is inherent
  to a game launcher.
* `--own-name=org.droposs.client.SingleInstance`: Tauri single-instance D-Bus
  name (`dbus_id` = app ID + `.SingleInstance`), used for `drop://` deep links.

`--filesystem=host` has an important side effect: `HOME` is the **real host
home**, while `XDG_DATA_HOME` / `XDG_CONFIG_HOME` remain per-app under
`~/.var/app/org.droposs.client/`. Do not assume `HOME == ~/.var/app/$APP_ID`.

### Wrappers

The upstream binary is installed as `/app/bin/drop-app-bin`; `/app/bin/drop-app`
is a wrapper that:

* keeps `argv[0]` as `drop-app` (window class / StartupWMClass),
* links the host's `~/.steam` into the app home if `HOME` is ever per-app
  (normally unnecessary because of `--filesystem=host`).

`/app/bin/umu-run` forwards Proton/umu launches to the host:

```
Drop -> /app/bin/umu-run -> flatpak-spawn --host <host-umu> ...
```

Critical details:

* `flatpak-spawn` requires the equals form: `--env=VAR=VALUE`. The form
  `--env VAR=VALUE` fails with `Missing argument for --env`.
* Use `--clear-env`, copy the environment except a denylist, then restore a
  normal host `PATH` (`/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin`
  plus `$HOME/.local/bin`).
* Forward `GAMEID`, `PROTONPATH`, `WINEPREFIX`, `UMU_NO_PROTON`, display/audio
  variables and user launch env vars.
* Drop: `LD_LIBRARY_PATH LD_PRELOAD PYTHONPATH PYTHONHOME PYTHONUSERBASE
  GI_TYPELIB_PATH GSETTINGS_SCHEMA_DIR GIO_EXTRA_MODULES PULSE_SERVER
  PULSE_CLIENTCONFIG ALSA_CONFIG_PATH ALSA_CONFIG_DIR XAUTHORITY
  DBUS_SESSION_BUS_ADDRESS`, plus `FLATPAK_*`, `container*`.
  They point at sandbox-only paths (`/app`, `/run/flatpak/...`) that do not
  exist on the host and break host Python/Proton/audio/X11/D-Bus.
* Do not unset `DBUS_SESSION_BUS_ADDRESS` / `XAUTHORITY` before calling
  `flatpak-spawn` itself; `--clear-env` applies to the child, while
  flatpak-spawn needs its own bus access.
* Absolute paths are preserved because per-app data
  (`/home/user/.var/app/org.droposs.client/...`) and `--filesystem=host` paths
  resolve to the same paths on the host.
* Host `umu-launcher` is a runtime dependency. `DROP_HOST_UMU` overrides the
  executable (`flatpak override --user --env=DROP_HOST_UMU=...`).
* The zero-argument probe exits successfully immediately. Drop only checks that
  `Command::output()` succeeded, so umu still appears installed; a missing host
  umu produces a clear error at launch time.

### Proton discovery

Drop's auto-discovery is hardcoded to:

```
/usr/share/steam/compatibilitytools.d/
$HOME/.steam/root/compatibilitytools.d/
```

and only accepts a directory containing both `proton` and
`compatibilitytool.vdf` (`desktop/src-tauri/process/src/compat.rs`).

* **Official Steam Proton** versions live in
  `~/.local/share/Steam/steamapps/common/` and do not have
  `compatibilitytool.vdf`. They are not discovered. Install GE-Proton with
  ProtonUp-Qt (creates a proper compatibility tool), or add a
  `compatibilitytool.vdf` and use the manual path picker.
* **Flatpak Steam** keeps tools in
  `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d`.
  Drop does not scan it; use **Settings → Proton → Manual Proton Layers**.
* Inside our Flatpak, `/usr/share/steam/...` resolves to the GNOME runtime,
  not the host. Only the `$HOME/.steam/root` path is useful. System-wide
  SteamOS tools are invisible; copy/symlink them into the home path.
* On Steam Deck, native Steam's path is
  `~/.steam/root/compatibilitytools.d` (symlink to
  `~/.local/share/Steam/compatibilitytools.d`). ProtonUp-Qt with the native
  Steam path is the reliable setup.
* After adding a layer, restart Drop so the settings page refetches the list.

Launching a discovered layer through our Flatpak still requires host
`umu-run` (see above). On SteamOS, install umu-launcher per-user if possible,
or point `DROP_HOST_UMU` at a host-accessible executable.

### Native Linux games

"Native (direct)" games execute inside the sandbox with host filesystem
access. Most work because the runtime is close to Fedora 44. Missing runtime
libraries require selecting the "Steam Linux Runtime (umu-run)" option (host
execution). 32-bit-only games need 32-bit runtime libraries, which are not
provided.

### Known limitations

* **Autostart** writes to the app's private config directory, so "start on
  login" does not create a working host autostart entry.
* **Tray icon** is disabled because `libayatana-appindicator` is not in the
  GNOME runtime; the app logs `appindicator library not available at runtime`.
* **Window resizing**: upstream creates the main window with
  `.decorations(false)` and `.shadow(false)` in
  `desktop/src-tauri/src/lib.rs`; the frontend only calls
  `window.startDragging()` and implements no resize grips. There is no
  maximum-size hint, so the window is technically resizable, but there is no
  titlebar/border to grab. On KDE use Alt+right-drag or Alt+F8, or add a KWin
  Window Rule for class `drop-app` forcing "No titlebar and frame" = No. A
  proper fix is upstream: enable decorations or call Tauri's
  `startResizeDragging` from edge hitboxes.
* The package uses a prebuilt upstream binary, not a source build.

### Updating Drop

1. Update `VERSION`, `RPM`, `RPM_URL`, `RPM_SHA256` in
   `packages/org.droposs.client/package.env`.
2. Update the release in `org.droposs.client.metainfo.xml`.
3. Run `./build.sh org.droposs.client` and the full testing checklist.
4. Verify no new/missing libraries with `ldd` inside the installed app.
5. Publish.

## Testing

### Generic

```sh
bash -n build.sh scripts/*.sh packages/*/prepare.sh packaging/* 2>/dev/null || true
appstreamcli validate --no-net packages/org.droposs.client/org.droposs.client.metainfo.xml
desktop-file-validate packages/org.droposs.client/org.droposs.client.desktop
python3 -c 'import yaml; yaml.safe_load(open(".github/workflows/pages.yml"))'
./build.sh --list
./build.sh
```

### Drop: install and run

```sh
flatpak --user install -y --reinstall ./dist/org.droposs.client.flatpak
flatpak info --show-permissions org.droposs.client

# No unresolved libraries:
flatpak run --command=ldd org.droposs.client /app/bin/drop-app-bin | grep 'not found' || echo none

# Host execution through flatpak-spawn:
flatpak run --command=sh org.droposs.client \
  -c 'flatpak-spawn --host sh -c "id -un; echo ok"'

# umu bridge probe:
flatpak run --command=sh org.droposs.client -c '/app/bin/umu-run; echo probe=$?'

# Start the app, then kill it:
(flatpak run org.droposs.client >/tmp/drop-run.log 2>&1 &)
sleep 8
flatpak ps | grep droposs
flatpak kill org.droposs.client
tail -20 ~/.var/app/org.droposs.client/data/drop/drop.log
```

Expected log lines:

```
INFO | client/src/compat.rs - Some("umu-run")
INFO | src/lib.rs - initialized drop client
WARN | src/lib.rs - appindicator library not available at runtime, disabling system tray icon
```

If the current ref came from a signed remote, reinstalling the unsigned local
bundle fails with `GPG verification enabled, but no signatures found`.
`flatpak uninstall org.droposs.client` first, or install from the signed remote.

### Drop: fake host umu test

```sh
cat > fake-umu-run <<'EOF'
#!/bin/sh
env | grep -E '^(GAMEID|PROTONPATH|WINEPREFIX|UMU_NO_PROTON|PULSE_SERVER|XAUTHORITY|DBUS_SESSION_BUS_ADDRESS|PYTHONUSERBASE|GI_TYPELIB_PATH|FLATPAK_ID|PATH)=' | sort
EOF
chmod +x fake-umu-run

flatpak run --command=sh org.droposs.client -c \
  'GAMEID=test PROTONPATH=/home/harry/proton WINEPREFIX=/home/harry/pfx \
   UMU_NO_PROTON=1 DROP_HOST_UMU=/path/to/fake-umu-run \
   /app/bin/umu-run /bin/true'
```

Expected: `GAMEID`, `PROTONPATH`, `WINEPREFIX`, `UMU_NO_PROTON` and a normal
host `PATH` are present; `PULSE_SERVER`, `XAUTHORITY`,
`DBUS_SESSION_BUS_ADDRESS`, `PYTHONUSERBASE`, `GI_TYPELIB_PATH`, `FLATPAK_ID`
and `LD_LIBRARY_PATH` are absent.

### Drop: native host executable

```sh
printf '#!/bin/sh\necho native-ok\n' > native-test.sh
chmod +x native-test.sh
flatpak run --command=sh org.droposs.client -c "$PWD/native-test.sh"
```

## Environment quirks in this container

The real home `/home/harry` is root-owned and **not writable**; use a
project-local Flatpak installation:

```sh
export XDG_DATA_HOME="$PWD/.flatpak-data"
export XDG_CACHE_HOME="$PWD/.flatpak-cache"
export XDG_CONFIG_HOME="$PWD/.flatpak-config"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
```

`org.gnome.Platform//50` is installed there. Add Flathub with the same
`XDG_DATA_HOME` if needed:

```sh
flatpak --user remote-add --if-not-exists flathub \
  https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak --user install -y flathub org.gnome.Platform//50
```

`flatpak-builder` is not installed and is not used.

## Common failures

| Symptom | Cause / fix |
| --- | --- |
| `flatpak-spawn: Missing argument for --env` | Use `--env=VAR=VALUE`, not `--env VAR=VALUE`. |
| Host umu sees `PULSE_SERVER=/run/flatpak/...` and no audio | Denylist not applied or `--clear-env` missing. |
| `umu-run was not found on the host` | Install umu-launcher on the host or set `DROP_HOST_UMU`. |
| Drop starts but Proton options are missing | The `/app/bin/umu-run` probe must exist and be executable; Drop only checks spawn success, not exit status. |
| Proton layers not listed | Drop only scans `~/.steam/root/compatibilitytools.d` (plus the runtime's `/usr/share/steam`) and requires `proton` + `compatibilitytool.vdf`. Official Steam Proton in `steamapps/common` is not discovered; use GE-Proton/ProtonUp-Qt or manual add. Flatpak Steam's `.var/app/.../compatibilitytools.d` path must be added manually. |
| Game fails with missing `.so` | Native game needs a library not in the runtime; use the umu option to run on the host. |
| WebKit window blank / GPU issues | Check runtime branch and drivers; `WEBKIT_DISABLE_DMABUF_RENDERER=1` is a last-resort workaround, not a default. |
| Cannot resize the Drop window | Upstream undecorated window with no resize grips. Use Alt+right-drag / Alt+F8 on KDE or a KWin rule forcing decorations. Not a Flatpak issue. |
| Permissions differ from `finish-args.txt` | Re-run `flatpak build-finish` (just rebuild) and check `flatpak info --show-permissions`. |
| Pages install fails with GPG error | `GPGKey` missing/stale in `.flatpakrepo`, or summary/commit not signed. Re-export the public key. |
| Workflow fails to install a runtime | The runtime is not on Flathub; add its `RUNTIME_REPO` to the workflow's runtime step. |
| `--reinstall` of local bundle fails after testing the signed remote | Uninstall the signed-remote ref first. |

## Do not

* Do not remove `--filesystem=host`, `--device=all` or
  `--talk-name=org.freedesktop.Flatpak` from the Drop package without an
  explicit request; game launching stops working.
* Do not run umu/pressure-vessel inside the sandbox. Host `flatpak-spawn` is
  the supported path.
* Do not assume `HOME` is the per-app home in Drop; the `host` filesystem
  permission makes it the real home.
* Do not rename desktop files/icons away from the app ID.
* Do not publish an unsigned official remote; clients should not need
  `--no-gpg-verify`.
* Do not commit `repo/`, `dist/`, `work/`, downloaded RPMs or
  `.flatpak-data/`; they are intentionally gitignored.
