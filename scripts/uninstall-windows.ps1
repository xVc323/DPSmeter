$ErrorActionPreference = 'Stop'
$ModId = 'DPSMeter'
$DryRun = $env:DPSMETER_DRY_RUN -eq '1'
function Write-Step([string]$Message) { Write-Host "[DPSMeter] $Message" }
function Invoke-Step([scriptblock]$Block, [string]$Description) { if ($DryRun) { Write-Step "DRY-RUN: $Description" } else { & $Block } }
function Find-Sts2Executable {
    if ($env:STS2_EXE -and (Test-Path -LiteralPath $env:STS2_EXE)) { return (Resolve-Path -LiteralPath $env:STS2_EXE).Path }
    $roots = @("$env:ProgramFiles(x86)\Steam\steamapps\common", "$env:ProgramFiles\Steam\steamapps\common") | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
    foreach ($root in $roots) {
        $hit = Get-ChildItem -LiteralPath $root -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Slay the Spire 2.exe', 'SlayTheSpire2.exe') } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw 'Could not find Slay the Spire 2 executable. Set STS2_EXE.'
}
function Convert-SaveLinks {
    if ($env:DPSMETER_UNLINK_SAVES -ne '1') {
        Write-Step 'Leaving save links intact. Set DPSMETER_UNLINK_SAVES=1 to convert links back to copies.'
        return
    }
    foreach ($base in @((Join-Path $env:APPDATA 'SlayTheSpire2'), (Join-Path $env:APPDATA 'Godot\app_userdata\SlayTheSpire2'), (Join-Path $env:LOCALAPPDATA 'SlayTheSpire2'))) {
        $steam = Join-Path $base 'steam'
        if (-not (Test-Path -LiteralPath $steam)) { continue }
        Get-ChildItem -LiteralPath $steam -Directory -Recurse -Filter saves | Where-Object { $_.FullName -match '\\modded\\profile[^\\]+\\saves$' } | ForEach-Object {
            if ($_.LinkType -eq 'Junction' -or $_.Attributes.ToString().Contains('ReparsePoint')) {
                $copy = "$($_.FullName).copy-before-unlink-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
                Invoke-Step { Copy-Item -LiteralPath $_.FullName -Destination $copy -Recurse -Force } "Copy linked saves to $copy"
                Invoke-Step { Remove-Item -LiteralPath $_.FullName -Recurse -Force } "Remove link $($_.FullName)"
                Invoke-Step { Move-Item -LiteralPath $copy -Destination $_.FullName } "Restore save copy"
            }
        }
    }
}
if (Get-Process | Where-Object { $_.ProcessName -like '*Slay*Spire*' }) { throw 'Quit Slay the Spire 2 before uninstalling.' }
$Exe = Find-Sts2Executable
$ModDir = Join-Path (Join-Path (Split-Path -Parent $Exe) 'mods') $ModId
if (Test-Path -LiteralPath $ModDir) {
    Invoke-Step { Remove-Item -LiteralPath $ModDir -Recurse -Force } "Remove $ModDir"
    Write-Step "Removed $ModDir"
} else {
    Write-Step "$ModId is not installed at $ModDir"
}
Convert-SaveLinks
Write-Step 'Uninstall complete. Saves were not deleted.'
