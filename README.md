# termux-setmeup (template)

This is a non-TUI Rust template for Termux setup automation.
It keeps the same project regime used in `termux-setmeup`: remote build/sync scripts, CI/release workflows, tag-driven releases, and npm/crates publishing scaffolding.

## What this template does
- installs latest Termux APK from F-Droid via adb when explicitly triggered
- installs embedded extra packages via apt when explicitly triggered
- installs embedded apt tweak config into Termux apt.conf.d when explicitly triggered
- keeps project scripts/workflows for packaging and release automation

## CLI options

### `--install-termux`
Installs the latest Termux APK from F-Droid to the connected Android device via `adb`.

Requirements:
1. `adb` must be installed and available in `PATH`.
2. `adb devices` must show exactly one connected device in `device` state.

Example:
```bash
adb devices
termux-setmeup --install-termux
```

### `--dry-run`
Prints the actions without executing them. Use this to preview install behavior.

Example:
```bash
termux-setmeup --dry-run --install-termux
```

### `--install-extra-packages`
Installs extra packages using:
```bash
apt install -y --no-install-recommends <embedded-packages...>
```

Requirements:
1. `ssh` must be installed and available in `PATH`.
2. `--remote user@host[:port]` is required (`:port` optional, defaults to `22`).

Package source:
1. The list comes from `res/extra-packages.txt`.
2. It is compiled into the binary at build time.

Example:
```bash
termux-setmeup --install-extra-packages --remote user@host:22
```

### `--install-apt-tweaks`
Uploads embedded apt config and installs it into:
```bash
$PREFIX/etc/apt/apt.conf.d/my-apt.conf
```

Requirements:
1. `ssh` must be installed and available in `PATH`.
2. `--remote user@host[:port]` is required (`:port` optional, defaults to `22`).

Config source:
1. The file comes from `res/my-apt.conf`.
2. It is compiled into the binary at build time.

Example:
```bash
termux-setmeup --install-apt-tweaks --remote user@host:22
```

### `--remote`
Remote target in `user@host[:port]` format, used by remote actions such as `--install-extra-packages` and `--install-apt-tweaks`.
If `:port` is omitted, port `22` is used.

Example:
```bash
termux-setmeup --install-extra-packages --remote user@host:2222
```

### `--help`
Shows available options and usage.

Example:
```bash
termux-setmeup --help
```

### `--version`
Prints the executable version.

Example:
```bash
termux-setmeup --version
```

## Quick examples
```bash
termux-setmeup --install-termux
termux-setmeup --dry-run --install-termux
termux-setmeup --install-extra-packages --remote user@host:22
termux-setmeup --install-apt-tweaks --remote user@host:22
termux-setmeup --install-extra-packages --remote user@host
```

## First-run manual steps (required)
After running `--install-termux` for the first time:

1. Open Termux on the device.
2. Enable shared storage directories (on the phone).
```bash
termux-setup-storage
```
3. Run package update.
```bash
pkg update
```
4. Install required packages (`dropbear` and `termux-auth`).
```bash
pkg install -y dropbear termux-auth
```
5. Set password for later login.
```bash
passwd
```
6. Start dropbear on custom bind target.
```bash
dropbear -p ip:port
```

These manual steps are required because upcoming actions depend on dropbear being up and reachable on the remote.

## Included automation
- `scripts/gen-ssh-key.sh`
- `scripts/sync-remote.sh`
- `scripts/build-local.sh`
- `scripts/run-rustci.sh`
- `scripts/run-rustci-remote.sh`
- `scripts/push-tag.sh`
- `scripts/set-repo-vars.sh`

## Notes
- Repository/workflow placeholders still need your repo URL/user values.
- Default remote paths in scripts are examples; adjust for your environment.
