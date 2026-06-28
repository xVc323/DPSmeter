$ErrorActionPreference = 'Stop'

$ModId = 'DPSMeter'
$Repo = if ($env:DPSMETER_REPO) { $env:DPSMETER_REPO } else { 'xvc323/DPSmeter' }
$DryRun = $env:DPSMETER_DRY_RUN -eq '1'

function Write-Step([string]$Message) { Write-Host "[DPSMeter] $Message" }
function Invoke-Step([scriptblock]$Block, [string]$Description) {
    if ($DryRun) { Write-Step "DRY-RUN: $Description" } else { & $Block }
}
function Backup-Path([string]$Path) {
    if (Test-Path -LiteralPath $Path) {
        $Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
        $Backup = "$Path.backup-before-dpsmeter-$Stamp"
        Invoke-Step { Copy-Item -LiteralPath $Path -Destination $Backup -Recurse -Force } "Copy $Path to $Backup"
        Write-Step "Backed up $Path -> $Backup"
    }
}
function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]
    foreach ($key in @('HKCU:\Software\Valve\Steam', 'HKLM:\Software\WOW6432Node\Valve\Steam', 'HKLM:\Software\Valve\Steam')) {
        try {
            $props = Get-ItemProperty -Path $key -ErrorAction Stop
            if ($props.SteamPath) { $roots.Add($props.SteamPath) }
            if ($props.InstallPath) { $roots.Add($props.InstallPath) }
        } catch {}
    }
    foreach ($candidate in @("$env:ProgramFiles(x86)\Steam", "$env:ProgramFiles\Steam")) {
        if ($candidate -and (Test-Path -LiteralPath $candidate)) { $roots.Add($candidate) }
    }
    return $roots | Select-Object -Unique
}
function Find-Sts2Executable {
    if ($env:STS2_EXE -and (Test-Path -LiteralPath $env:STS2_EXE)) { return (Resolve-Path -LiteralPath $env:STS2_EXE).Path }
    if ($env:STS2_DIR -and (Test-Path -LiteralPath $env:STS2_DIR)) {
        $hit = Get-ChildItem -LiteralPath $env:STS2_DIR -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Slay the Spire 2.exe', 'SlayTheSpire2.exe') } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    foreach ($steam in Get-SteamRoots) {
        $common = Join-Path $steam 'steamapps\common'
        if (-not (Test-Path -LiteralPath $common)) { continue }
        $hit = Get-ChildItem -LiteralPath $common -Recurse -File -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in @('Slay the Spire 2.exe', 'SlayTheSpire2.exe') } |
            Select-Object -First 1
        if ($hit) { return $hit.FullName }
    }
    throw 'Could not find Slay the Spire 2 executable. Set STS2_EXE or STS2_DIR.'
}
function Get-Package([string]$TempDir) {
    $Zip = Join-Path $TempDir 'DPSMeter.zip'
    if ($env:DPSMETER_PACKAGE) {
        if (-not (Test-Path -LiteralPath $env:DPSMETER_PACKAGE)) { throw "DPSMETER_PACKAGE not found: $env:DPSMETER_PACKAGE" }
        Invoke-Step { Copy-Item -LiteralPath $env:DPSMETER_PACKAGE -Destination $Zip -Force } "Copy local package to $Zip"
    } else {
        $Url = "https://github.com/$Repo/releases/latest/download/DPSMeter.zip"
        Invoke-Step { Invoke-WebRequest -Uri $Url -OutFile $Zip } "Download $Url"
    }
    $Payload = Join-Path $TempDir 'payload'
    Invoke-Step { Expand-Archive -LiteralPath $Zip -DestinationPath $Payload -Force } "Expand $Zip"
    $Manifest = Join-Path $Payload 'DPSMeter.json'
    $Dll = Join-Path $Payload 'DPSMeter.dll'
    if (-not (Test-Path -LiteralPath $Manifest)) { throw 'Package missing DPSMeter.json' }
    if (-not (Test-Path -LiteralPath $Dll)) { throw 'Package missing DPSMeter.dll' }
    $Json = Get-Content -LiteralPath $Manifest -Raw | ConvertFrom-Json
    if ($Json.id -ne 'DPSMeter' -or $Json.has_dll -ne $true -or $Json.has_pck -ne $false -or $Json.affects_gameplay -ne $false) {
        throw 'DPSMeter.json failed safety validation: affects_gameplay/has_dll/has_pck mismatch.'
    }
    return $Payload
}
function Get-Sts2UserRoots {
    $candidates = @(
        (Join-Path $env:APPDATA 'SlayTheSpire2'),
        (Join-Path $env:APPDATA 'Godot\app_userdata\SlayTheSpire2'),
        (Join-Path $env:LOCALAPPDATA 'SlayTheSpire2')
    )
    return $candidates | Where-Object { $_ -and (Test-Path -LiteralPath $_) }
}
function Share-Saves {
    foreach ($root in Get-Sts2UserRoots) {
        $steamRoot = Join-Path $root 'steam'
        if (-not (Test-Path -LiteralPath $steamRoot)) { continue }
        Get-ChildItem -LiteralPath $steamRoot -Directory | ForEach-Object {
            $account = $_.FullName
            Get-ChildItem -LiteralPath $account -Directory -Filter 'profile*' | ForEach-Object {
                $normalSaves = Join-Path $_.FullName 'saves'
                if (-not (Test-Path -LiteralPath $normalSaves)) { return }
                $moddedProfile = Join-Path (Join-Path $account 'modded') $_.Name
                $moddedSaves = Join-Path $moddedProfile 'saves'
                Invoke-Step { New-Item -ItemType Directory -Path $moddedProfile -Force | Out-Null } "Create $moddedProfile"
                if (Test-Path -LiteralPath $moddedSaves) {
                    Backup-Path $moddedSaves
                    Invoke-Step { Remove-Item -LiteralPath $moddedSaves -Recurse -Force } "Remove existing $moddedSaves"
                }
                try {
                    Invoke-Step { New-Item -ItemType Junction -Path $moddedSaves -Target $normalSaves | Out-Null } "Create Junction $moddedSaves -> $normalSaves"
                    Write-Step "Linked modded saves to normal saves for $($_.Name)"
                } catch {
                    Write-Step "Junction failed; copying saves instead: $($_.Exception.Message)"
                    Invoke-Step { Copy-Item -LiteralPath $normalSaves -Destination $moddedSaves -Recurse -Force } "Copy $normalSaves to $moddedSaves"
                }
            }
        }
    }
}

if (Get-Process | Where-Object { $_.ProcessName -like '*Slay*Spire*' }) { throw 'Quit Slay the Spire 2 before installing.' }
$Exe = Find-Sts2Executable
$ModsRoot = Join-Path (Split-Path -Parent $Exe) 'mods'
$ModDir = Join-Path $ModsRoot $ModId
$Temp = Join-Path ([System.IO.Path]::GetTempPath()) "dpsmeter-install-$([guid]::NewGuid())"
New-Item -ItemType Directory -Path $Temp -Force | Out-Null
try {
    $Payload = Get-Package $Temp
    Backup-Path $ModDir
    Invoke-Step { New-Item -ItemType Directory -Path $ModDir -Force | Out-Null } "Create $ModDir"
    Invoke-Step { Copy-Item -LiteralPath (Join-Path $Payload 'DPSMeter.dll') -Destination (Join-Path $ModDir 'DPSMeter.dll') -Force } "Install DLL"
    Invoke-Step { Copy-Item -LiteralPath (Join-Path $Payload 'DPSMeter.json') -Destination (Join-Path $ModDir 'DPSMeter.json') -Force } "Install manifest"
    Share-Saves
    Write-Step "Install complete: $ModDir"
} finally {
    if (Test-Path -LiteralPath $Temp) { Remove-Item -LiteralPath $Temp -Recurse -Force -ErrorAction SilentlyContinue }
}
