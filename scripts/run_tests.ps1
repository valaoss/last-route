$root = Split-Path -Parent $PSScriptRoot
$godot = Join-Path $root "tools\godot_console.exe"
& $godot --headless --path $root res://tests/test_runner.tscn 2>&1 | Where-Object { $_ -match '^\s+(ok|FAIL)|RESULT|^[A-Z][A-Za-z]+$|SCRIPT ERROR' }
exit $LASTEXITCODE
