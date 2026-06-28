#!/usr/bin/env bash
set -euo pipefail

MOD_ID="DPSMeter"
DRY_RUN="${DPSMETER_DRY_RUN:-0}"

log() { printf '[DPSMeter] %s\n' "$*"; }
fail() { printf '[DPSMeter] ERROR: %s\n' "$*" >&2; exit 1; }
run() { if [[ "$DRY_RUN" == "1" ]]; then printf '[DPSMeter] DRY-RUN: '; printf '%q ' "$@"; printf '\n'; else "$@"; fi; }

find_sts2_dir() {
  if [[ -n "${STS2_DIR:-}" ]]; then
    printf '%s\n' "$STS2_DIR"
    return
  fi
  local candidate="$HOME/Library/Application Support/Steam/steamapps/common/Slay the Spire 2"
  if [[ -d "$candidate/SlayTheSpire2.app/Contents/MacOS" ]]; then
    printf '%s\n' "$candidate"
    return
  fi
  local found
  found="$(find "$HOME/Library/Application Support/Steam/steamapps/common" -maxdepth 3 -path '*/SlayTheSpire2.app/Contents/MacOS' -type d 2>/dev/null | head -1 || true)"
  [[ -n "$found" ]] || fail "Could not find Slay the Spire 2. Set STS2_DIR=/path/to/'Slay the Spire 2'."
  dirname "$(dirname "$(dirname "$found")")"
}

main() {
  if pgrep -f "Slay the Spire 2" >/dev/null 2>&1; then
    fail "Slay the Spire 2 appears to be running. Quit the game before uninstalling."
  fi
  local sts2_dir mod_dir
  sts2_dir="$(find_sts2_dir)"
  mod_dir="$sts2_dir/SlayTheSpire2.app/Contents/MacOS/mods/$MOD_ID"
  if [[ -e "$mod_dir" ]]; then
    run rm -rf "$mod_dir"
    log "Removed $mod_dir"
  else
    log "$MOD_ID is not installed at $mod_dir"
  fi
  log "Uninstall complete. Saves were not deleted."
}

main "$@"
