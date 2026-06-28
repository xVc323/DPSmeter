# DPS Meter for Slay the Spire 2

DPS Meter is a local, English-only Slay the Spire 2 overlay mod. It is designed for direct local install instead of Steam Workshop distribution. It shows each player's damage for the current combat and for the whole run.

It is explicitly display-only:

```json
"affects_gameplay": false
```

STS2 only blocks multiplayer joins when **gameplay-affecting** mods differ. DPS Meter is a non-gameplay UI overlay, so mismatches with unmodded players are allowed by the game's multiplayer compatibility check.

## Features

- Current-combat damage per player
- Total run damage per player
- Last hit and max hit values
- Draggable in-game Godot overlay
- DLL-only install; no separate `.pck` is required
- Compact and side-hidden UI states
- English UI text only
- Automatic save sharing between normal and modded profiles

## Quick install from GitHub

The installer downloads `DPSMeter.zip` from the latest GitHub Release unless `DPSMETER_PACKAGE` points at a local zip.

### macOS install

```bash
curl -fsSL https://raw.githubusercontent.com/xvc323/DPSmeter/main/scripts/install-macos.sh | bash
```

### macOS uninstall

```bash
curl -fsSL https://raw.githubusercontent.com/xvc323/DPSmeter/main/scripts/uninstall-macos.sh | bash
```

### Windows install

Open PowerShell and run:

```powershell
irm https://raw.githubusercontent.com/xvc323/DPSmeter/main/scripts/install-windows.ps1 | iex
```

### Windows uninstall

```powershell
irm https://raw.githubusercontent.com/xvc323/DPSmeter/main/scripts/uninstall-windows.ps1 | iex
```

## Save handling

STS2 stores saves separately once any mod is loaded:

```text
profile1/saves
modded/profile1/saves
```

The installer backs up any existing modded save folder and then links the modded save folder to the normal save folder:

```text
modded/profile1/saves -> profile1/saves
```

This keeps progression continuous when switching between unmodded STS2 and DPS Meter. Uninstall does **not** delete saves and leaves the save link intact by default.

If you really want uninstall to convert the save link back into a separate copy:

macOS:

```bash
DPSMETER_UNLINK_SAVES=1 bash scripts/uninstall-macos.sh
```

Windows:

```powershell
$env:DPSMETER_UNLINK_SAVES = "1"; .\scripts\uninstall-windows.ps1
```

## Build a release package

From a machine with Slay the Spire 2 installed:

```bash
scripts/package-release.sh
```

This creates:

```text
dist/DPSMeter.zip
```

The zip contains:

```text
DPSMeter.dll
DPSMeter.json
```

Upload `dist/DPSMeter.zip` to a GitHub Release. The install scripts download:

```text
https://github.com/xvc323/DPSmeter/releases/latest/download/DPSMeter.zip
```

## Manual install layout

Build or obtain these two files:

- `DPSMeter.dll`
- `DPSMeter.json`

### macOS manual path

STS2 reads local mods from the `mods` folder next to the game executable. On macOS the executable is inside the app bundle:

```text
Slay the Spire 2/SlayTheSpire2.app/Contents/MacOS/mods/DPSMeter/
```

Expected final layout:

```text
Slay the Spire 2/
  SlayTheSpire2.app/
    Contents/
      MacOS/
        mods/
          DPSMeter/
            DPSMeter.dll
            DPSMeter.json
```

### Windows manual path

STS2 uses the `mods` folder next to the Windows executable. The installer finds the executable and installs to:

```text
<folder containing Slay the Spire 2.exe>\mods\DPSMeter\
```

## Build requirements

The mod build references game assemblies from your local Slay the Spire 2 install. On this Mac, the default Steam path is detected automatically:

```text
~/Library/Application Support/Steam/steamapps/common/Slay the Spire 2/SlayTheSpire2.app/Contents/Resources/data_sts2_macos_arm64
```

Requirements:

- macOS or Windows
- .NET SDK 10
- Godot .NET SDK 4.5.1
- Slay the Spire 2 installed locally

Run:

```bash
dotnet build
```

If Steam is installed elsewhere, pass the path explicitly:

```bash
dotnet build -p:Sts2Dir="$HOME/Library/Application Support/Steam/steamapps/common/Slay the Spire 2"
```

## Local repository checks

```bash
python3 -m unittest discover -s tests -v
```

These checks validate the local mod identity, display-only manifest, English-only localization, documentation, installer safety contracts, and source invariants.

## Attribution

DPS Meter is based on the MIT-licensed `BAIGUANGMEI/STS2-DamageTracker` project:

https://github.com/BAIGUANGMEI/STS2-DamageTracker

The upstream MIT license is preserved in `LICENSE`, and attribution details are in `NOTICE`.
