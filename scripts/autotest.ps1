param(
	[Parameter(Mandatory = $true)][ValidateSet("look", "ride", "arena", "perf", "gasrun", "hood")][string]$Scenario,
	[ValidateSet("track", "arena", "gasrun", "hood")][string]$Level = "track",
	[int]$TimeoutSec = 420
)
$ErrorActionPreference = "Stop"
$root = Split-Path -Parent $PSScriptRoot
$out = Join-Path $root ".autotest"
New-Item -ItemType Directory -Force $out | Out-Null
Get-ChildItem $out -Filter "*.png" | Remove-Item
$godot = Join-Path $root "tools\godot_console.exe"
$args = "--path `"$root`" --resolution 1280x720 --quit-after 30000 -- --$Level --autotest=$Scenario --out=$($out -replace '\\','/')"
$p = Start-Process $godot -ArgumentList $args -PassThru -RedirectStandardOutput "$out\stdout.txt" -RedirectStandardError "$out\stderr.txt"
if (-not $p.WaitForExit($TimeoutSec * 1000)) { $p.Kill(); Write-Output "TIMEOUT" }
Get-Content "$out\stdout.txt", "$out\stderr.txt" | Where-Object { $_ -match 'SCRIPT ERROR|ERROR|autotest' -and $_ -notmatch 'Jolt' } | Select-Object -First 40
