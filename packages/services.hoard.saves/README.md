# Hoard (Flatpak)

Upstream: <https://github.com/rleeon/hoard> · Site: <https://hoard.services>

Hoard is a versioned game-save backup and sync system. It ships as three
binaries that must live in the same directory, and this package installs all
three:

| Binary | Role |
| --- | --- |
| `hoard-desktop` | Tauri v2 GUI (WebKitGTK 4.1) — the app in the menu |
| `hoardd` | the resident sync daemon; owns the engine and listens on a Unix socket |
| `hoard` | thin CLI client of `hoardd` |

Source release:

```
Hoard_1.3.0_amd64.deb   (29 MB)
https://github.com/rleeon/hoard/releases/download/v1.3.0/Hoard_1.3.0_amd64.deb
sha256 3281634d02bf313059e84d62bb3e490b7cb43877bfec0721a23748dc5242fedc
```

The `.deb` is the desktop bundle, not a server package: upstream builds the
same release artefacts for Windows, macOS, Linux and SteamOS. `prepare.sh`
unpacks it and installs the three binaries plus the desktop entry, icons and
metainfo. Nothing is compiled and no SDK is needed.

Upstream also maintains a Flatpak manifest at
`flatpak/services.hoard.saves.yml` in their repository. This package follows
its decisions (same ID, same runtime, same permissions minus the tray) rather
than inventing its own.

## Runtime

`org.gnome.Platform//50` must provide:

* `libwebkit2gtk-4.1.so.0` and `libjavascriptcoregtk-4.1.so.0` (the GUI)
* GTK 3, libsoup 3
* libsecret (credential store over the session bus)
* glibc >= 2.34 (the binaries need at most 2.34; the runtime has 2.42)

Check after a runtime change:

```sh
flatpak run --command=ldd services.hoard.saves /app/bin/hoard-desktop \
  | grep 'not found' || echo none
```

If the GNOME runtime ever drops WebKitGTK 4.1, stay on the last branch that
has it or switch runtimes; there is no 6.0 build of this app.

## Permissions (finish-args.txt)

| Permission | Why |
| --- | --- |
| `--filesystem=host` | Hoard scans for saves wherever they are: Steam libraries on other drives, Proton/Wine prefixes, emulator folders, hand-picked paths. Narrower grants silently miss drives. |
| `--filesystem=/var/mnt` | `host` excludes `/var`, which is where rpm-ostree distros (Bazzite, Silverblue, Kinoite, Aurora) mount extra disks. |
| `--share=network` | Cloud sync (Hoard Cloud or self-hosted). |
| `--share=ipc`, `--device=dri` | WebKitGTK shared memory and GPU. |
| `--socket=wayland`, `--socket=fallback-x11` | The window. |
| `--talk-name=org.freedesktop.secrets` | The daemon keeps the cloud token in libsecret. Without it the store is absent and credentials fall back to a file inside the sandbox. |
| `--talk-name=org.freedesktop.Notifications` | Backup success/failure notifications. |
| `--own-name=dev.hoard.desktop.SingleInstance` | Tauri single-instance (the name comes from `tauri.conf.json`, not the Flatpak ID): a second launch raises the existing window instead of starting a second copy. |

`--filesystem=host` has an important side effect: `HOME` is the **real host
home**. Hoard's own state still lives under `~/.var/app/services.hoard.saves/`
because `XDG_CONFIG_HOME` and `XDG_DATA_HOME` stay per-app.

## The daemon: how it works here

Hoard's engine is `hoardd`, a per-user resident daemon. In a Flatpak there is
no `systemctl` and the host's systemd never reads anything written into the
sandbox's `$XDG_CONFIG_HOME`, so upstream routes login start through
`org.freedesktop.portal.Background`.

1. **The app starts it.** `hoard-desktop` spawns `hoardd` from `/app/bin`,
   detached (`setsid`, stdio to `/dev/null`, own session). Closing the window
   does **not** stop the daemon, and Flatpak keeps the sandbox alive while any
   process is in it.
2. **Login start is opt-in.** Settings → "Sync in the background at login"
   asks the portal once (the first request may show a dialog). The portal
   writes `~/.config/autostart/services.hoard.saves.desktop` on the **host**,
   whose command is `flatpak run --command=hoardd services.hoard.saves`.
   That file is the persistent daemon; it is the only mechanism a Flatpak has,
   and it cannot be enabled at install time.
3. **One daemon per sandbox.** The socket is `$XDG_RUNTIME_DIR/hoard/hoardd.sock`
   and lives in the app's private runtime directory, shared by every
   `flatpak run` of this app. A GUI launched later joins the sandbox the
   autostart daemon created and talks to it over that socket; a separately
   launched `flatpak run --command=hoard …` does the same.

Verify it by hand:

```sh
# what the autostart entry does (starts the sandbox if it is not running)
flatpak run --command=hoardd services.hoard.saves &

# a second launch joins the same sandbox and reaches the same daemon
flatpak run --command=hoard services.hoard.saves whoami

# stop everything, daemon included
flatpak kill services.hoard.saves
```

### The one real limitation: process detection

Flatpak gives the app its own PID namespace. `--filesystem=host` exposes the
host's *files*, but not its process table — inside the sandbox `/proc` lists
only sandbox processes.

So `hoardd` cannot see your running games. In practice:

* "Back up the moment the game closes" (the `GameStopped` trigger) does not
  fire from process detection.
* Playtime tracking is blind.
* "Heavy process → scan for a new game" auto-detection does not fire.

Backups still happen: each tracked save has an inotify watcher inside the
sandbox, and writes schedule a `FilesystemSettled` backup; the hourly sweep and
the manual "back up now" button work too. The snapshots are the same, only the
trigger is file activity rather than process exit. This is inherent to Flatpak
and cannot be fixed in the manifest. If you need process-driven triggering,
run the native install of `hoardd` on the host instead.

## No tray icon

The GNOME 50 runtime does not ship `libayatana-appindicator` (upstream builds
it into their own Flatpak as a module; this repository extracts prebuilt
binaries and does not). Tauri logs:

```
WARN | src/lib.rs - tray icon backend panicked (missing libayatana-appindicator3 / libappindicator3?), continuing without a tray icon
```

The app works, but **the X button hides the window to a tray that does not
exist**. Two ways back:

* launch Hoard again from the menu — single-instance raises the existing
  window;
* turn off Settings → "Close to tray" so X actually quits the window (the
  daemon keeps running).

`flatpak kill services.hoard.saves` gets you out either way.

## CLI

`hoard` lives inside the sandbox, so it is not on the host `PATH`:

```sh
flatpak run --command=hoard services.hoard.saves saves
flatpak run --command=hoard services.hoard.saves doctor
flatpak run --command=hoard services.hoard.saves login --token <token>
```

An alias helps:

```sh
alias hoard='flatpak run --command=hoard services.hoard.saves'
```

## Known limitations

* **No tray** (see above).
* **No process detection** (see above).
* **No self-update.** `/app` is read-only; updates come from this remote. The
  app reports itself as managed and hides its own updater.
* **`hoard://` deep links** are exported through the desktop entry
  (`MimeType=x-scheme-handler/hoard`, `Exec=hoard-desktop %u`). If a host
  browser hands the OAuth callback to the Flatpak, it arrives as a second
  launch and the single-instance plugin forwards it to the running window.
* **A native Hoard and this one share the session bus name**
  `dev.hoard.desktop.SingleInstance`. With both installed, a Flatpak launch can
  forward to the native window (or vice versa). The two keep separate config,
  data and keyring entries, but do not run them at the same time.
* **Autostart needs a portal backend.** `xdg-desktop-portal` plus the desktop's
  implementation (GNOME/KDE) must be running on the host to grant the
  background request.

## Updating Hoard

1. Bump `VERSION`, `DEB`, `DEB_URL` and `DEB_SHA256` in `package.env`.
2. Update the release list in `services.hoard.saves.metainfo.xml`.
3. `./build.sh services.hoard.saves` and run the checks below.
4. Check `ldd` inside the installed app for new/missing libraries.
5. Publish.

## Testing

```sh
bash -n packages/services.hoard.saves/prepare.sh
appstreamcli validate --no-net packages/services.hoard.saves/services.hoard.saves.metainfo.xml
desktop-file-validate packages/services.hoard.saves/services.hoard.saves.desktop

./build.sh services.hoard.saves
flatpak --user install -y --reinstall ./dist/services.hoard.saves.flatpak
flatpak info --show-permissions services.hoard.saves

# No unresolved libraries:
flatpak run --command=ldd services.hoard.saves /app/bin/hoard-desktop | grep 'not found' || echo none
flatpak run --command=ldd services.hoard.saves /app/bin/hoardd        | grep 'not found' || echo none

# GUI + daemon:
(flatpak run services.hoard.saves >/tmp/hoard-run.log 2>&1 &)
sleep 10
ps -eo pid,sid,args | grep -E '/app/bin/hoardd|hoard-desktop' | grep -v grep
flatpak ps | grep services.hoard.saves

# The daemon outlives the window: kill only the GUI process, then check again.
tail -20 ~/.var/app/services.hoard.saves/cache/hoard/logs/hoardd.log

# Autostart path (no GUI):
flatpak kill services.hoard.saves
(flatpak run --command=hoardd services.hoard.saves >/tmp/hoardd.log 2>&1 &)
sleep 8
flatpak run --command=hoard services.hoard.saves whoami   # reaches the daemon
grep 'client connected' /tmp/hoardd.log
flatpak kill services.hoard.saves
```

Expected log lines:

```
INFO hoardd: listening address=/run/user/1000/hoard/hoardd.sock ... engine=true
INFO hoardd::server: client connected client=hoard-desktop 1.3.0 (commands) protocol=1
WARN hoard_desktop_lib: tray icon backend panicked (...), continuing without a tray icon
WARN hoardd::engine: couldn't start the engine error=no session. ...
```

The last warning is expected in a container without a session bus or until you
sign in; with a signed-in session the engine starts instead.
