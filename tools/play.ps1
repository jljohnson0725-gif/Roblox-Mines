<#
    play.ps1 -- open the generated place in Roblox Studio.

    Exists because .rbxlx has no file association by default, so double-clicking
    the place hands it to a text editor. This resolves Studio at RUN TIME rather
    than baking in a path: the install lives under a version-hashed folder that
    changes on every Studio update, so a hardcoded path would break silently.

    Run it via Play.cmd in the project root, or directly:
        powershell -ExecutionPolicy Bypass -File tools\play.ps1
        powershell -ExecutionPolicy Bypass -File tools\play.ps1 -DryRun
#>
param([switch]$DryRun)

$root = Split-Path -Parent $PSScriptRoot
$place = Join-Path $root 'BrainrotMines.rbxlx'

if (-not (Test-Path $place)) {
    Write-Host "Place file not found:" -ForegroundColor Red
    Write-Host "  $place"
    Write-Host ""
    Write-Host "Build it first:  python tools\build_place.py"
    if (-not $DryRun) { Read-Host 'Press Enter to close' }
    exit 1
}

$searchRoots = @(
    "$env:LOCALAPPDATA\Roblox\Versions",
    "$env:PROGRAMFILES\Roblox\Versions",
    "${env:PROGRAMFILES(X86)}\Roblox\Versions"
)

$studio = $searchRoots |
    Where-Object { Test-Path $_ } |
    ForEach-Object { Get-ChildItem $_ -Filter 'RobloxStudioBeta.exe' -Recurse -ErrorAction SilentlyContinue } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $studio) {
    Write-Host "Roblox Studio not found in any of:" -ForegroundColor Red
    $searchRoots | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
    Write-Host "If Studio is installed elsewhere, open it and use File -> Open instead."
    if (-not $DryRun) { Read-Host 'Press Enter to close' }
    exit 1
}

Write-Host "Studio : $($studio.FullName)" -ForegroundColor DarkGray
Write-Host "Place  : $place" -ForegroundColor DarkGray

if ($DryRun) {
    Write-Host "dry run - not launching." -ForegroundColor Yellow
    exit 0
}

Start-Process $studio.FullName -ArgumentList "`"$place`""
Write-Host ""
Write-Host "Launching Brainrot Mines... (Studio takes a few seconds)" -ForegroundColor Green
Start-Sleep -Seconds 2
