#!/usr/bin/env bash
set -euo pipefail

MOD_ID="DPSMeter"
MOD_ZIP="DPSMeter.zip"
DEFAULT_REPO="${DPSMETER_REPO:-xvc323/DPSmeter}"
DRY_RUN="${DPSMETER_DRY_RUN:-0}"

log() { printf '[DPSMeter] %s\n' "$*"; }
fail() { printf '[DPSMeter] ERROR: %s\n' "$*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == "1" ]]; then printf '[DPSMeter] DRY-RUN: '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Missing required command: $1"
}

check_requirements() {
  require_command curl
  require_command unzip
  require_command find
  require_command pgrep
  require_command mktemp
}

backup_mod_dir() {
  local mod_dir="$1"
  local mods_root="$2"
  local stamp backup_root backup
  stamp="$(date +%Y%m%d-%H%M%S)"
  backup_root="$(dirname "$mods_root")/dpsmeter-backups"
  backup="$backup_root/${MOD_ID}.backup-before-dpsmeter-${stamp}"
  if [[ -e "$mod_dir" || -L "$mod_dir" ]]; then
    run mkdir -p "$backup_root"
    run cp -a "$mod_dir" "$backup"
    log "Backed up $mod_dir -> $backup"
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

  local descriptor="$temp_dir/payload/${MOD_ID}.json"
  grep -Eq '"id"[[:space:]]*:[[:space:]]*"DPSMeter"' "$descriptor" || fail "Package descriptor has the wrong mod id."
  grep -Eq '"has_dll"[[:space:]]*:[[:space:]]*true' "$descriptor" || fail "Package descriptor must declare has_dll=true."
  grep -Eq '"has_pck"[[:space:]]*:[[:space:]]*false' "$descriptor" || fail "Package descriptor must declare has_pck=false."
  grep -Eq '"affects_gameplay"[[:space:]]*:[[:space:]]*false' "$descriptor" || fail "Package descriptor must declare affects_gameplay=false."
}

install_payload() {
  local sts2_dir="$1"
  local payload_dir="$2"
  # STS2 scans the mods folder next to OS.GetExecutablePath; on macOS that is inside the app bundle.
  local mods_root="$sts2_dir/SlayTheSpire2.app/Contents/MacOS/mods"
  local mod_dir="$mods_root/$MOD_ID"
  backup_mod_dir "$mod_dir" "$mods_root"
  run mkdir -p "$mod_dir"
  run cp "$payload_dir/${MOD_ID}.dll" "$mod_dir/${MOD_ID}.dll"
  run cp "$payload_dir/${MOD_ID}.json" "$mod_dir/${MOD_ID}.json"
  log "Installed $MOD_ID to $mod_dir"
}

main() {
  check_requirements
  if pgrep -f "Slay the Spire 2" >/dev/null 2>&1; then
    fail "Slay the Spire 2 appears to be running. Quit the game before installing."
  fi
  local sts2_dir
  sts2_dir="$(find_sts2_dir)"
  DPSMETER_TEMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${DPSMETER_TEMP_DIR:-}"' EXIT
  fetch_payload "$DPSMETER_TEMP_DIR"
  install_payload "$sts2_dir" "$DPSMETER_TEMP_DIR/payload"
  log "Install complete. Launch Slay the Spire 2 and enable $MOD_ID if needed."
}

main "$@"
