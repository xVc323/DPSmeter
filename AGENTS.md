# DPSMeter — Slay the Spire 2 Local Overlay Mod

This repository contains a local, English-only Slay the Spire 2 DPS meter mod adapted from the MIT-licensed `BAIGUANGMEI/STS2-DamageTracker` project.

## Core Contract

- Keep `DPSMeter.json` display-only with `"affects_gameplay": false`.
- Do not add gameplay, networking, RNG, reward, card, relic, HP, or matchmaking mutations.
- Preserve upstream MIT attribution in `LICENSE` and `NOTICE`.
- Keep user-facing UI text in English under `assets/localization/eng/dps_meter.json`.

## Main Files

| File | Purpose |
| --- | --- |
| `src/ModEntry.cs` | STS2 mod initializer and Harmony hook registration |
| `src/RunDPSMeterService.cs` | Resolved-damage aggregation and local run state |
| `src/ReflectionHelpers.cs` | STS2 runtime identity fallback helpers |
| `src/DPSMeterOverlay.cs` | Godot `CanvasLayer` overlay UI |
| `DPSMeter.json` | Local STS2 mod descriptor |
| `mod_manifest.json` | Godot/export packaging metadata |

## Verification

Run repository contract tests before claiming completion:

```bash
python3 -m unittest discover -s tests -v
```

A full build requires macOS/Windows, Godot .NET SDK 4.5.1, .NET SDK 10, and a local Slay the Spire 2 installation containing `sts2.dll`, `0Harmony.dll`, and `Steamworks.NET.dll`.
