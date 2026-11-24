#!/usr/bin/env bash
# Install AeroHUD: installs the Spoon into Hammerspoon, loads it from
# ~/.hammerspoon/init.lua, and hooks it into AeroSpace's exec-on-workspace-change.
#
# Safe to re-run: every step is skipped if it is already done, and re-running
# the curl one-liner updates to the latest release. Files are backed up to
# <file>.aerohud.bak before they are changed.
#
# Everything runs from main(), called on the last line, so a download that is
# cut off part way through does nothing.

set -euo pipefail

GITHUB_REPO="Maverick-Chow/AeroHUD"

usage() {
  cat <<EOF
Usage:
  curl -fsSL https://github.com/$GITHUB_REPO/releases/latest/download/install.sh | bash
  curl -fsSL ... | bash -s -- [options]
  ./install.sh [options]          (from a clone of the repo)

Options:
  --copy        from a clone: copy the Spoon instead of symlinking it to the repo
  --no-reload   only edit files; don't restart Hammerspoon or reload AeroSpace

Environment:
  AEROHUD_VERSION   release tag to install, e.g. v0.1.0 (default: latest)
  AEROHUD_ZIP_URL   download the Spoon zip from this URL instead
EOF
}

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
info() { printf '  • %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
die()  { printf '\n\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }

backup() {
  [ -s "$1" ] && [ ! -f "$1.aerohud.bak" ] && cp "$1" "$1.aerohud.bak" && info "Backed up $1"
  return 0
}

# Run a command, killing it after $1 seconds. Both hs and aerospace can block
# indefinitely while the other app is busy, and macOS has no `timeout`.
with_timeout() {
  local secs=$1 pid watchdog rc
  shift
  "$@" >/dev/null 2>&1 &
  pid=$!
  ( sleep "$secs"; kill "$pid" 2>/dev/null ) >/dev/null 2>&1 &
  watchdog=$!
  disown "$watchdog" # no "Terminated" job notice when we kill it below
  wait "$pid" && rc=0 || rc=$?
  kill "$watchdog" 2>/dev/null || true
  return "$rc"
}

# Run Lua in Hammerspoon.
hs_run() { with_timeout 5 "$HS_BIN" -t 3 -c "$1"; }

hs_running() { pgrep -xq Hammerspoon; }

# Restart Hammerspoon so it re-reads init.lua.
restart_hammerspoon() {
  if [ -n "${HS_BIN:-}" ] && hs_running && hs_run 'return true'; then
    # hs.reload() drops the IPC connection, so schedule it instead of calling it.
    hs_run 'hs.timer.doAfter(0.1, hs.reload)' || true
    sleep 0.5
  else
    if hs_running; then
      osascript -e 'quit app "Hammerspoon"' >/dev/null 2>&1 || true
      for _ in $(seq 20); do hs_running || break; sleep 0.25; done
    fi
    open -g -a Hammerspoon
  fi
}

# Wait until Hammerspoon answers over IPC with the Spoon loaded.
wait_for_hammerspoon() {
  for _ in $(seq 20); do
    hs_run 'assert(spoon.AeroHUD)' && return 0
    sleep 0.5
  done
  return 1
}

check_dependencies() {
  bold "Checking dependencies"

  [ "$(uname)" = "Darwin" ] || die "AeroHUD only runs on macOS."

  local missing=0
  if open -Ra Hammerspoon >/dev/null 2>&1; then
    ok "Hammerspoon"
  else
    warn "Hammerspoon is not installed:  brew install --cask hammerspoon"
    missing=1
  fi

  AEROSPACE_BIN="$(command -v aerospace || true)"
  for p in /opt/homebrew/bin/aerospace /usr/local/bin/aerospace; do
    [ -z "$AEROSPACE_BIN" ] && [ -x "$p" ] && AEROSPACE_BIN="$p"
  done
  if [ -n "$AEROSPACE_BIN" ]; then
    ok "AeroSpace ($AEROSPACE_BIN)"
  else
    warn "AeroSpace is not installed:  brew install --cask nikitabobko/tap/aerospace"
    missing=1
  fi

  [ "$missing" = 0 ] || die "Install the missing dependencies above, then run this script again."
}

install_spoon() {
  bold "Installing the Spoon"
  mkdir -p "$HS_DIR/Spoons"

  if [ -n "$REPO_DIR" ]; then
    # Running from a clone: link to it so `git pull` updates the Spoon.
    local src="$REPO_DIR/AeroHUD.spoon"
    if [ "$COPY" = 1 ]; then
      rm -rf "$SPOON_DST"
      cp -R "$src" "$SPOON_DST"
      ok "Copied to $SPOON_DST"
    elif [ -L "$SPOON_DST" ] && [ "$(readlink "$SPOON_DST")" = "$src" ]; then
      ok "Already linked at $SPOON_DST"
    else
      rm -rf "$SPOON_DST"
      ln -s "$src" "$SPOON_DST"
      ok "Linked $SPOON_DST -> $src"
    fi
    return
  fi

  # Running from curl: download the release zip.
  local url="${AEROHUD_ZIP_URL:-}"
  if [ -z "$url" ]; then
    if [ -n "${AEROHUD_VERSION:-}" ]; then
      url="https://github.com/$GITHUB_REPO/releases/download/$AEROHUD_VERSION/AeroHUD.spoon.zip"
    else
      url="https://github.com/$GITHUB_REPO/releases/latest/download/AeroHUD.spoon.zip"
    fi
  fi
  TMP_DIR="$(mktemp -d)"
  info "Downloading $url"
  curl -fsSL --retry 2 "$url" -o "$TMP_DIR/AeroHUD.spoon.zip" || die "Download failed: $url"
  unzip -q "$TMP_DIR/AeroHUD.spoon.zip" -d "$TMP_DIR" || die "The download is not a valid zip."
  [ -f "$TMP_DIR/AeroHUD.spoon/init.lua" ] || die "The download doesn't contain AeroHUD.spoon."

  local version
  version="$(sed -n 's/^obj\.version = "\(.*\)"/\1/p' "$TMP_DIR/AeroHUD.spoon/init.lua")"
  if [ -L "$SPOON_DST" ]; then
    warn "Replacing the existing link to $(readlink "$SPOON_DST")"
  fi
  rm -rf "$SPOON_DST"
  mv "$TMP_DIR/AeroHUD.spoon" "$SPOON_DST"
  ok "Installed AeroHUD ${version:+v$version }to $SPOON_DST"
}

configure_hammerspoon() {
  bold "Configuring Hammerspoon"

  # Nothing to back up if init.lua is new.
  local fresh=0
  [ -s "$HS_INIT" ] || fresh=1
  touch "$HS_INIT"

  if ! grep -q 'require *(\{0,1\} *["'"'"']hs\.ipc' "$HS_INIT"; then
    [ "$fresh" = 1 ] || backup "$HS_INIT"
    printf '\nrequire("hs.ipc") -- needed for the `hs` CLI that AeroSpace calls\n' >> "$HS_INIT"
    ok "Enabled hs.ipc in init.lua"
  else
    ok "hs.ipc already enabled"
  fi

  if ! grep -q 'loadSpoon *(\{0,1\} *["'"'"']AeroHUD' "$HS_INIT"; then
    [ "$fresh" = 1 ] || backup "$HS_INIT"
    cat >> "$HS_INIT" <<'EOF'

hs.loadSpoon("AeroHUD")
spoon.AeroHUD:configure({
  position = "bottom", -- "bottom" | "center" | "top"
  duration = 0.8,
  showAppIcons = true,
  theme = "auto",
}):start()
EOF
    ok "Added AeroHUD to init.lua"
  else
    ok "AeroHUD already in init.lua"
  fi

  # The hs CLI is installed by Hammerspoon itself, so it can only be done from
  # init.lua. Use the Homebrew prefix: /usr/local/bin may not exist on Apple Silicon.
  local prefix
  prefix="$( (command -v brew >/dev/null && brew --prefix) || echo /usr/local)"
  HS_BIN="$(command -v hs || true)"
  [ -z "$HS_BIN" ] && [ -x "$prefix/bin/hs" ] && HS_BIN="$prefix/bin/hs"

  if [ -n "$HS_BIN" ]; then
    ok "hs CLI ($HS_BIN)"
  elif [ "$RELOAD" = 0 ]; then
    [ "$fresh" = 1 ] || backup "$HS_INIT"
    printf 'hs.ipc.cliInstall("%s")\n' "$prefix" >> "$HS_INIT"
    HS_BIN="$prefix/bin/hs"
    warn "The hs CLI will be installed into $prefix/bin the next time Hammerspoon loads."
  else
    [ "$fresh" = 1 ] || backup "$HS_INIT"
    printf 'hs.ipc.cliInstall("%s")\n' "$prefix" >> "$HS_INIT"
    info "Installing the hs CLI into $prefix/bin (restarting Hammerspoon)"
    restart_hammerspoon
    for _ in $(seq 40); do [ -x "$prefix/bin/hs" ] && break; sleep 0.25; done
    [ -x "$prefix/bin/hs" ] || die "The hs CLI did not appear. Open the Hammerspoon console, run hs.ipc.cliInstall(\"$prefix\"), then run this script again."
    HS_BIN="$prefix/bin/hs"
    ok "hs CLI ($HS_BIN)"
  fi

  if [ "$RELOAD" = 1 ]; then
    restart_hammerspoon
    wait_for_hammerspoon || die "Hammerspoon didn't load AeroHUD. Check the Hammerspoon console for errors."
    ok "Reloaded Hammerspoon, AeroHUD is running"
  fi
}

configure_aerospace() {
  bold "Configuring AeroSpace"

  # AeroSpace reads ~/.aerospace.toml or $XDG_CONFIG_HOME/aerospace/aerospace.toml.
  local xdg_toml="${XDG_CONFIG_HOME:-$HOME/.config}/aerospace/aerospace.toml"
  if [ -f "$HOME/.aerospace.toml" ] && [ -f "$xdg_toml" ]; then
    die "Both ~/.aerospace.toml and $xdg_toml exist; AeroSpace refuses to load either. Remove one and re-run."
  elif [ -f "$HOME/.aerospace.toml" ]; then
    TOML="$HOME/.aerospace.toml"
  elif [ -f "$xdg_toml" ]; then
    TOML="$xdg_toml"
  else
    # With no config AeroSpace uses its built-in defaults; start from those so
    # adding our callback doesn't drop the default key bindings.
    TOML="$HOME/.aerospace.toml"
    local default_toml
    default_toml="$(dirname "$(dirname "$(readlink -f "$AEROSPACE_BIN")")")/Resources/default-config.toml"
    [ -f "$default_toml" ] || default_toml="/Applications/AeroSpace.app/Contents/Resources/default-config.toml"
    if [ -f "$default_toml" ]; then
      cp "$default_toml" "$TOML"
      info "Created $TOML from AeroSpace's default config"
    else
      : > "$TOML"
      info "Created an empty $TOML"
    fi
  fi
  info "Config: $TOML"

  local hs_cmd status
  hs_cmd="$HS_BIN"' -c "spoon.AeroHUD:show(\"$AEROSPACE_FOCUSED_WORKSPACE\", \"$AEROSPACE_PREV_WORKSPACE\")"'

  if grep -q 'AeroHUD' "$TOML"; then
    ok "AeroHUD callback already present"
  else
    backup "$TOML"
    ROLLBACK="$(mktemp)"
    cp "$TOML" "$ROLLBACK"
    set +e
    HS_CMD="$hs_cmd" perl -0777 -e '
      my $hs = $ENV{HS_CMD};
      my $s = do { local $/; <STDIN> };
      my $str = qr/'"'"'[^'"'"'\n]*'"'"'|"(?:[^"\\\n]|\\.)*"/;
      if ($s =~ /^[ \t]*exec-on-workspace-change\s*=\s*\[\s*((?:$str\s*,\s*)*)($str)\s*,?\s*\]/m) {
        # Chain onto the existing shell command, e.g. ["/bin/bash", "-c", "..."].
        # Save the match position first: the next regex resets @- and @+.
        my ($start, $len, $last, $rest) = ($-[2], $+[2] - $-[2], $2, $1);
        my @args = ($rest =~ /($str)/g);
        my $flag = @args ? substr($args[-1], 1, -1) : "";
        exit 3 unless $flag =~ /^-[a-z]*c$/;
        my $q = substr($last, 0, 1);
        my $body = substr($last, 1, -1);
        $body =~ s/[\s;]+$//;
        my $add = $hs;
        if ($q eq "\"") { $add =~ s/\\/\\\\/g; $add =~ s/"/\\"/g; }
        my $sep = $body =~ /&$/ ? " " : "; ";
        substr($s, $start, $len) = $q . $body . $sep . $add . $q;
        print $s;
      } elsif ($s =~ /^[ \t]*exec-on-workspace-change\s*=/m) {
        exit 3;
      } else {
        # Top-level keys must come before any [table], so put it at the very top.
        print "# AeroHUD: show the HUD on every workspace switch\n",
              "exec-on-workspace-change = [\x27/bin/bash\x27, \x27-c\x27,\n",
              "  \x27$hs\x27\n]\n\n", $s;
      }
    ' < "$TOML" > "$TOML.tmp"
    status=$?
    set -e
    if [ "$status" = 0 ]; then
      mv "$TOML.tmp" "$TOML"
      ok "Added the AeroHUD callback to exec-on-workspace-change"
    else
      rm -f "$TOML.tmp"
      warn "Couldn't safely edit your existing exec-on-workspace-change. Add this to the end of its shell command yourself:"
      printf '\n    ; %s\n\n' "$hs_cmd"
      exit 1
    fi
  fi

  [ "$RELOAD" = 1 ] || return 0

  pgrep -xq AeroSpace || { info "Starting AeroSpace"; open -a AeroSpace; sleep 2; }
  if with_timeout 10 "$AEROSPACE_BIN" reload-config; then
    ok "Reloaded AeroSpace config"
  else
    if [ -n "${ROLLBACK:-}" ]; then
      cp "$ROLLBACK" "$TOML"
      with_timeout 10 "$AEROSPACE_BIN" reload-config || true
      die "AeroSpace didn't accept the new config, so it was rolled back. Run 'aerospace reload-config' to see the error."
    fi
    die "aerospace reload-config failed. Run it yourself to see the error."
  fi
}

main() {
  COPY=0
  RELOAD=1
  for arg in "$@"; do
    case "$arg" in
      --copy) COPY=1 ;;
      --no-reload) RELOAD=0 ;;
      -h|--help) usage; exit 0 ;;
      *) echo "Unknown option: $arg" >&2; usage >&2; exit 2 ;;
    esac
  done

  # From a clone, BASH_SOURCE is this file and the Spoon sits next to it. Piped
  # from curl there is no file, so the Spoon is downloaded instead.
  REPO_DIR=""
  local self="${BASH_SOURCE[0]:-}"
  if [ -f "$self" ] && [ -f "$(dirname "$self")/AeroHUD.spoon/init.lua" ]; then
    REPO_DIR="$(cd "$(dirname "$self")" && pwd)"
  fi

  HS_DIR="$HOME/.hammerspoon"
  HS_INIT="$HS_DIR/init.lua"
  SPOON_DST="$HS_DIR/Spoons/AeroHUD.spoon"
  TMP_DIR=""
  trap 'if [ -n "$TMP_DIR" ]; then rm -rf "$TMP_DIR"; fi' EXIT

  check_dependencies
  install_spoon
  configure_hammerspoon
  configure_aerospace

  echo
  if [ "$RELOAD" = 1 ]; then
    bold "Done! Switch workspaces to see the HUD."
  else
    bold "Done! Reload Hammerspoon and run 'aerospace reload-config' to start AeroHUD."
  fi
}

main "$@"
