# okraPDF for Windows — one-shot build.
# Produces dist\okrapdf.exe (self-contained; WebView2 runtime required at
# runtime, which ships with Windows 10/11 and Edge).
param(
  [switch]$SkipUi
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot

$tools = Join-Path $env:LOCALAPPDATA 'Programs'
$env:Path = "$tools\go\bin;$tools\node;$tools\mingw64\bin;$env:Path"
$env:CGO_ENABLED = '1'

if (-not $SkipUi) {
    Push-Location (Join-Path $root 'ui')
    try {
        if (-not (Test-Path 'node_modules')) {
            npm.cmd install
        }
        npm.cmd run typecheck
        npm.cmd run build
    } finally {
        Pop-Location
    }
}

Push-Location $root
try {
    go test ./...
    # Generate the Windows resource object (icon + version info) via windres.
    $rcDir = Join-Path $root 'cmd\okrapdf'
    $syso = Join-Path $rcDir 'okrapdf.syso'
    if (Test-Path $syso) { Remove-Item $syso -Force }
    Push-Location $rcDir
    try {
        windres okrapdf.rc -O coff -o okrapdf.syso
    } finally {
        Pop-Location
    }
    New-Item -ItemType Directory -Force -Path (Join-Path $root 'dist') | Out-Null
    go build -ldflags "-H windowsgui" -o (Join-Path $root 'dist\okrapdf.exe') ./cmd/okrapdf
    Write-Host "Built dist\okrapdf.exe"
} finally {
    Pop-Location
}
