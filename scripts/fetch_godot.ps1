param([string]$Version = "4.7.2-stable")
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$tools = Join-Path $root "tools"
New-Item -ItemType Directory -Force $tools | Out-Null
$exe = Join-Path $tools "godot.exe"
if (Test-Path $exe) { Write-Output "Godot already present: $exe"; exit 0 }
$zipName = "Godot_v${Version}_win64.exe.zip"
$url = "https://github.com/godotengine/godot/releases/download/$Version/$zipName"
$zip = Join-Path $tools $zipName
Invoke-WebRequest $url -OutFile $zip
Expand-Archive $zip -DestinationPath $tools -Force
Remove-Item $zip
Get-ChildItem $tools -Filter "Godot_v*_win64.exe" | Where-Object Name -notmatch "console" | Rename-Item -NewName "godot.exe"
Get-ChildItem $tools -Filter "Godot_v*_win64_console.exe" | Rename-Item -NewName "godot_console.exe"
Write-Output "Installed: $exe"
