# Builds the release Windows app and packages it into a setup .exe.
#
#   powershell -ExecutionPolicy Bypass -File tools\build-windows-installer.ps1
#   powershell -ExecutionPolicy Bypass -File tools\build-windows-installer.ps1 -SkipFlutterBuild
#
# Needs Flutter, Visual Studio (or Build Tools) with the C++ workload, and
# Inno Setup 6 (`winget install JRSoftware.InnoSetup`). The installer is
# written to build\installer\noote-setup-<version>.exe.

param(
    # Package the existing build\windows\x64\runner\Release without rebuilding.
    [switch]$SkipFlutterBuild
)

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# Version from pubspec.yaml ("version: 1.2.3+4" -> "1.2.3").
$versionLine = Select-String -Path 'pubspec.yaml' -Pattern '^version:\s*([0-9]+\.[0-9]+\.[0-9]+)' | Select-Object -First 1
if ($null -eq $versionLine) { throw 'Could not read the version from pubspec.yaml.' }
$version = $versionLine.Matches[0].Groups[1].Value

if (-not $SkipFlutterBuild) {
    Write-Host "Building Noote $version for Windows (release)..."
    flutter build windows --release
    if ($LASTEXITCODE -ne 0) { throw 'flutter build windows failed.' }
}
if (-not (Test-Path 'build\windows\x64\runner\Release\noote.exe')) {
    throw 'build\windows\x64\runner\Release\noote.exe not found. Run without -SkipFlutterBuild.'
}

# Inno Setup compiler: per-user (winget --scope user) or machine-wide install.
$iscc = @(
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe",
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe"
) | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($null -eq $iscc) { throw 'Inno Setup 6 not found. Install it with: winget install JRSoftware.InnoSetup' }

# Microsoft C++ runtime DLLs to bundle next to noote.exe.
$isccArgs = @("/DAppVersion=$version")
$vswhere = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
$crtDir = $null
if (Test-Path $vswhere) {
    $vsPath = & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    if ($vsPath) {
        $crtDir = Get-ChildItem -Path "$vsPath\VC\Redist\MSVC\*\x64\Microsoft.VC*.CRT" -Directory -ErrorAction SilentlyContinue |
            Sort-Object FullName -Descending | Select-Object -First 1
    }
}
if ($null -ne $crtDir) {
    $isccArgs += "/DVCRedistDir=$($crtDir.FullName)"
} else {
    Write-Warning 'Visual C++ runtime DLLs not found; the installer will rely on the PC having the VC++ Redistributable.'
}

Write-Host 'Packaging installer...'
& $iscc @isccArgs 'windows\installer\noote.iss'
if ($LASTEXITCODE -ne 0) { throw 'Inno Setup failed.' }

$out = Join-Path $root "build\installer\noote-setup-$version.exe"
Write-Host ''
Write-Host "Installer ready: $out"
