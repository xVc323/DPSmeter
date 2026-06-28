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
if (Get-Process | Where-Object { $_.ProcessName -like '*Slay*Spire*' }) { throw 'Quit Slay the Spire 2 before uninstalling.' }
$Exe = Find-Sts2Executable
$ModDir = Join-Path (Join-Path (Split-Path -Parent $Exe) 'mods') $ModId
if (Test-Path -LiteralPath $ModDir) {
    Invoke-Step { Remove-Item -LiteralPath $ModDir -Recurse -Force } "Remove $ModDir"
    Write-Step "Removed $ModDir"
} else {
    Write-Step "$ModId is not installed at $ModDir"
}
Write-Step 'Uninstall complete. Saves were not deleted.'
