#!/usr/bin/env bash
set -euo pipefail

MOD_ID="DPSMeter"
MOD_ZIP="DPSMeter.zip"
DEFAULT_REPO="${DPSMETER_REPO:-xvc323/DPSmeter}"
DRY_RUN="${DPSMETER_DRY_RUN:-0}"

log() { printf '[DPSMeter] %s\n' "$*"; }
fail() { printf '[DPSMeter] ERROR: %s\n' "$*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == "1" ]]; then printf '[DPSMeter] DRY-RUN: '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

backup_path() {
  local path="$1"
  local stamp
  stamp="$(date +%Y%m%d-%H%M%S)"
  local backup="${path}.backup-before-dpsmeter-${stamp}"
  if [[ -e "$path" || -L "$path" ]]; then
    run cp -a "$path" "$backup"
    log "Backed up $path -> $backup"
  fi
}

find_sts2_dir() {
  if [[ -n "${STS2_DIR:-}" ]]; then
    [[ -d "$STS2_DIR/SlayTheSpire2.app/Contents/MacOS" ]] || fail "STS2_DIR does not contain SlayTheSpire2.app/Contents/MacOS: $STS2_DIR"
    printf '%s\n' "$STS2_DIR"
    return
  fi

  local candidates=(
    "$HOME/Library/Application Support/Steam/steamapps/common/Slay the Spire 2"
    "$HOME/Applications/Slay the Spire 2"
    "/Applications/Slay the Spire 2"
  )
  local candidate
  for candidate in "${candidates[@]}"; do
    if [[ -d "$candidate/SlayTheSpire2.app/Contents/MacOS" ]]; then
      printf '%s\n' "$candidate"
      return
    fi
  done

  local found
  found="$(find "$HOME/Library/Application Support/Steam/steamapps/common" -maxdepth 3 -path '*/SlayTheSpire2.app/Contents/MacOS' -type d 2>/dev/null | head -1 || true)"
  [[ -n "$found" ]] || fail "Could not find Slay the Spire 2. Set STS2_DIR=/path/to/'Slay the Spire 2'."
  dirname "$(dirname "$(dirname "$found")")"
}

fetch_payload() {
  local temp_dir="$1"
  if [[ -n "${DPSMETER_PACKAGE:-}" ]]; then
    [[ -f "$DPSMETER_PACKAGE" ]] || fail "DPSMETER_PACKAGE not found: $DPSMETER_PACKAGE"
    log "Using local package $DPSMETER_PACKAGE"
    run cp "$DPSMETER_PACKAGE" "$temp_dir/$MOD_ZIP"
  else
    local url="https://github.com/${DEFAULT_REPO}/releases/latest/download/DPSMeter.zip"
    log "Downloading $url"
    run curl -fsSL "$url" -o "$temp_dir/$MOD_ZIP"
  fi

  run unzip -q "$temp_dir/$MOD_ZIP" -d "$temp_dir/payload"
  [[ -f "$temp_dir/payload/${MOD_ID}.dll" ]] || fail "Package missing ${MOD_ID}.dll"
  [[ -f "$temp_dir/payload/${MOD_ID}.json" ]] || fail "Package missing ${MOD_ID}.json"

  python3 - "$temp_dir/payload/${MOD_ID}.json" <<'PY'
import json, pathlib, sys
path = pathlib.Path(sys.argv[1])
data = json.loads(path.read_text())
assert data["id"] == "DPSMeter", data
assert data["has_dll"] is True, data
assert data["has_pck"] is False, data
assert data["affects_gameplay"] is False, data
PY
}

install_payload() {
  local sts2_dir="$1"
  local payload_dir="$2"
  # STS2 scans the mods folder next to OS.GetExecutablePath; on macOS that is inside the app bundle.
  local mods_root="$sts2_dir/SlayTheSpire2.app/Contents/MacOS/mods"
  local mod_dir="$mods_root/$MOD_ID"
  backup_path "$mod_dir"
  run mkdir -p "$mod_dir"
  run cp "$payload_dir/${MOD_ID}.dll" "$mod_dir/${MOD_ID}.dll"
  run cp "$payload_dir/${MOD_ID}.json" "$mod_dir/${MOD_ID}.json"
  log "Installed $MOD_ID to $mod_dir"
}

share_saves_for_account() {
  local account="$1"
  local profile_dir profile_name normal_saves modded_profile modded_saves
  for profile_dir in "$account"/profile*; do
    [[ -d "$profile_dir/saves" ]] || continue
    profile_name="$(basename "$profile_dir")"
    normal_saves="$profile_dir/saves"
    modded_profile="$account/modded/$profile_name"
    modded_saves="$modded_profile/saves"
    # Keep modded/profile*/saves pointed at profile*/saves so modded and unmodded progress stay in sync.
    run mkdir -p "$modded_profile"
    if [[ -L "$modded_saves" ]]; then
      local current_target
      current_target="$(readlink "$modded_saves")"
      if [[ "$current_target" == "$normal_saves" ]]; then
        log "Save link already exists for $profile_name"
        continue
      fi
      backup_path "$modded_saves"
      run rm "$modded_saves"
    elif [[ -e "$modded_saves" ]]; then
      backup_path "$modded_saves"
      run rm -rf "$modded_saves"
    fi
    run ln -s "$normal_saves" "$modded_saves"
    log "Linked $modded_saves -> $normal_saves"
  done
}

share_saves() {
  local user_root="$HOME/Library/Application Support/SlayTheSpire2/steam"
  [[ -d "$user_root" ]] || { log "No STS2 user save root found yet; skipping save sharing."; return; }
  local account
  for account in "$user_root"/*; do
    [[ -d "$account" ]] || continue
    share_saves_for_account "$account"
  done
}

main() {
  if pgrep -f "Slay the Spire 2" >/dev/null 2>&1; then
    fail "Slay the Spire 2 appears to be running. Quit the game before installing."
  fi
  local sts2_dir
  sts2_dir="$(find_sts2_dir)"
  DPSMETER_TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${DPSMETER_TEMP_DIR:-}"' EXIT
  fetch_payload "$DPSMETER_TEMP_DIR"
  install_payload "$sts2_dir" "$DPSMETER_TEMP_DIR/payload"
  share_saves
  log "Install complete. Launch Slay the Spire 2 and enable $MOD_ID if needed."
}

main "$@"
