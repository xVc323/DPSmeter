#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
CONFIG="${CONFIGURATION:-Release}"

mkdir -p "$DIST/payload"
rm -rf "$DIST/payload" "$DIST/DPSMeter.zip"
mkdir -p "$DIST/payload"

dotnet build "$ROOT/DPSMeter.csproj" -c "$CONFIG"
DLL="$ROOT/.godot/mono/temp/bin/$CONFIG/DPSMeter.dll"
[[ -f "$DLL" ]] || DLL="$(find "$ROOT/.godot/mono/temp/bin" -path "*/$CONFIG/DPSMeter.dll" -type f | head -1)"
[[ -f "$DLL" ]] || { echo "DPSMeter.dll not found after build" >&2; exit 1; }

cp "$DLL" "$DIST/payload/DPSMeter.dll"
cp "$ROOT/DPSMeter.json" "$DIST/payload/DPSMeter.json"
python3 - "$DIST/payload/DPSMeter.json" <<'PY'
import json, pathlib, sys
p = pathlib.Path(sys.argv[1])
d = json.loads(p.read_text())
assert d["id"] == "DPSMeter"
assert d["has_dll"] is True
assert d["has_pck"] is False
assert d["affects_gameplay"] is False
PY
(cd "$DIST/payload" && zip -q -r "$DIST/DPSMeter.zip" DPSMeter.dll DPSMeter.json)
echo "Created $DIST/DPSMeter.zip"
