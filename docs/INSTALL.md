# Installing AeroHUD

## Requirements

- macOS with [AeroSpace](https://github.com/nikitabobko/AeroSpace): `brew install --cask nikitabobko/tap/aerospace`
- [Hammerspoon](https://www.hammerspoon.org): `brew install --cask hammerspoon`

## Install

```sh
curl -fsSL https://github.com/Maverick-Chow/AeroHUD/releases/latest/download/install.sh | bash
```

Run the same command again to update to the latest release.

If you'd rather read the script before running it:

```sh
curl -fsSLO https://github.com/Maverick-Chow/AeroHUD/releases/latest/download/install.sh
less install.sh
bash install.sh
```

The script:

1. Checks that Hammerspoon and AeroSpace are installed, and tells you how to install whichever is missing.
2. Installs Hammerspoon's `hs` command-line tool if you don't have it. AeroSpace uses it to tell the HUD about workspace switches.
3. Downloads the latest `AeroHUD.spoon` release into `~/.hammerspoon/Spoons/`.
4. Adds AeroHUD to `~/.hammerspoon/init.lua` and reloads Hammerspoon.
5. Finds your AeroSpace config (`~/.aerospace.toml` or `~/.config/aerospace/aerospace.toml`) and adds the HUD to `exec-on-workspace-change`. If you already have a command there, such as a SketchyBar trigger, the HUD is chained after it rather than replacing it.
6. Routes your `move-node-to-workspace` key bindings through AeroHUD so moving a window animates on the HUD (see [Animating window moves](CONFIGURATION.md#animating-window-moves)).
7. Runs `aerospace reload-config`. If AeroSpace rejects the new config, the change is rolled back.

Steps that are already done are skipped, and every file the script changes is backed up first to `<file>.aerohud.bak`.

Options go after `bash -s --`, for example `curl -fsSL <url> | bash -s -- --no-reload`:

| Option | |
|---|---|
| `--no-reload` | Only edit files; don't restart Hammerspoon or reload AeroSpace |
| `--no-bindings` | Leave your `move-node-to-workspace` key bindings alone |
| `AEROHUD_VERSION=v0.1.0` | Set before `bash` to install a specific release instead of the latest |

## From source

```sh
git clone https://github.com/Maverick-Chow/AeroHUD.git
cd AeroHUD
./install.sh
```

From a clone, the Spoon is linked into `~/.hammerspoon/Spoons/` instead of downloaded, so a `git pull` updates it. Pass `--copy` to copy it instead.

## Manual install

1. Copy or link `AeroHUD.spoon` into `~/.hammerspoon/Spoons/`.
2. Add the contents of [`examples/init.lua`](../examples/init.lua) to `~/.hammerspoon/init.lua`, and run `hs.ipc.cliInstall()` once in the Hammerspoon console if you don't have the `hs` command. Reload Hammerspoon.
3. Add the callback from [`examples/aerospace.toml`](../examples/aerospace.toml) to your AeroSpace config and run `aerospace reload-config`.

To change how the HUD looks and behaves, see [CONFIGURATION.md](CONFIGURATION.md).
