# Drop Desktop Client

Flatpak package for the [Drop](https://github.com/Drop-OSS/drop) Desktop
Client, repackaged from the upstream RPM:

```
https://github.com/Drop-OSS/drop/releases/download/v0.4.0-rc-6/Drop.Desktop.Client-0.4.0-1.x86_64.rpm
```

## Runtime

`org.gnome.Platform//50` — the Fedora 44 build needs WebKitGTK 4.1, ICU 77,
glycin, GTK 3 and glibc 2.42. GNOME 50 provides all of them.

## Build

From the repository root:

```sh
./build.sh org.droposs.client
```

The result is `dist/org.droposs.client.flatpak`. Add
`KEEP_REPO=1` and a `GPG_SIGN` key to add to an existing shared repository.

## Sandbox permissions

| Permission | Why |
| --- | --- |
| `--filesystem=host` | Games can be installed anywhere, cloud saves and Proton installs are outside the app home, and game dirs must stay usable outside the sandbox. |
| `--share=network` | Drop server, downloads and updates. |
| `--share=ipc`, `--socket=x11`, `--socket=wayland` | UI and games; X11 is kept for XWayland. |
| `--socket=pulseaudio` | Audio. |
| `--device=all` | GPU, controllers/gamepads and other game devices. |
| `--talk-name=org.freedesktop.Flatpak` | Required for `flatpak-spawn --host` (Proton/umu launches). |
| `--talk-name=org.freedesktop.Notifications`, `--talk-name=org.kde.StatusNotifierWatcher` | Notifications and tray. |
| `--own-name=org.droposs.client.SingleInstance` | Tauri single-instance / `drop://` deep links. |

This is intentionally broad: it is a game launcher that runs arbitrary
downloaded executables from the host.

## Game launching

### Windows games / Proton (umu-run)

Drop looks for `umu-run` in `PATH`, `/app/share`, `/usr/local/share`,
`/usr/share` or `/opt`, then runs it with `GAMEID`, `PROTONPATH`, `WINEPREFIX`
and `UMU_NO_PROTON`.

This package ships `/app/bin/umu-run`, which forwards the launch to the
**host's** `umu-run` with `flatpak-spawn --host`:

```
Drop -> /app/bin/umu-run -> flatpak-spawn --host umu-run ...
```

So:

* **umu-launcher must be installed on the host.**
* Proton and the Steam Linux Runtime run outside the sandbox with the host's
  Python, drivers and Steam setup.
* Sandbox-only variables (`PULSE_SERVER`, `XAUTHORITY`,
  `DBUS_SESSION_BUS_ADDRESS`, Python/typelib paths, `FLATPAK_*`) are stripped
  before the host process starts; game launch variables and paths are
  preserved.
* Override the host executable if needed:

  ```sh
  flatpak override --user --env=DROP_HOST_UMU=/path/to/umu-run org.droposs.client
  ```

#### Proton discovery

Drop only auto-scans these two directories:

```
/usr/share/steam/compatibilitytools.d/       # inside Flatpak: the runtime's /usr, not the host's
~/.steam/root/compatibilitytools.d/
```

A directory is only accepted if it contains **both** `proton` and
`compatibilitytool.vdf`.

Consequences:

* **Official Steam Proton versions** (Proton Experimental, Proton 9.0, etc.)
  live in `~/.local/share/Steam/steamapps/common/` and do not ship a
  `compatibilitytool.vdf`, so Drop will not auto-detect them. Install
  **GE-Proton via ProtonUp-Qt** (which creates a proper tool in
  `compatibilitytools.d`) or add the path manually after providing a
  `compatibilitytool.vdf`.
* **Flatpak Steam** stores compatibility tools under
  `~/.var/app/com.valvesoftware.Steam/.local/share/Steam/compatibilitytools.d`.
  Drop does not scan that path; add the Proton directory with
  **Settings → Proton → Manual Proton Layers**.
* On **Steam Deck**, native Steam's compatibility tools are normally at
  `~/.steam/root/compatibilitytools.d` (a symlink to
  `~/.local/share/Steam/compatibilitytools.d`), which Drop can see through
  `--filesystem=host`. System-wide tools in SteamOS's `/usr/share/steam` are
  not visible inside the Flatpak runtime.

Because `--filesystem=host` is granted, `$HOME` inside the sandbox is the real
host home, so the `~/.steam/root` path works.

### Native Linux games

"Native (direct)" games execute inside the sandbox with host filesystem
access. Most work because the runtime is close to Fedora 44. Caveats:

* Missing runtime libraries cause the game to fail; select the
  "Steam Linux Runtime (umu-run)" option to run it on the host instead.
* 32-bit-only games need 32-bit runtime libraries, which are not provided.

## Known limitations

* **Autostart** writes to the app's private config directory, so "start on
  login" will not create a working host autostart entry.
* **Tray icon** is disabled because `libayatana-appindicator` is not in the
  GNOME runtime. The rest of the app works.
* **Window resizing**: Drop creates an undecorated window
  (`.decorations(false)`) and its frontend only implements window dragging,
  not resize handles. The window is technically resizable (it has no maximum
  size hint), but there is no titlebar or border to grab. On KDE, resize with
  **Alt+right-drag** or **Alt+F8**, or add a KWin Window Rule for class
  `drop-app` forcing **No titlebar and frame = No**. This is not
  Flatpak-specific; the real fix belongs upstream (enable decorations or add
  `startResizeDragging` handles).
* The upstream binary is prebuilt; this package does not compile Drop from
  source.

## Files

```
package.env                    package metadata and RPM source
prepare.sh                     downloads/extracts the RPM into the /app tree
finish-args.txt                sandbox permissions
drop-app                       launcher wrapper (argv[0], Steam fallback)
umu-run                        host umu-run bridge
org.droposs.client.desktop     desktop entry / drop:// handler
org.droposs.client.metainfo.xml
```
