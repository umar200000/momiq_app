$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$version = (Get-Content (Join-Path $appRoot '.flutter-version') -Raw).Trim()
$sdkPath = Join-Path $appRoot ".local/toolchains/flutter-$version"
$expectedCommit = 'f94f4fc76b4d74543ed9b085bbd75341ef65de22'
if (-not (Test-Path -LiteralPath $sdkPath)) {
    git clone --config core.longpaths=true --depth 1 --branch $version https://github.com/flutter/flutter.git $sdkPath
    if ($LASTEXITCODE -ne 0) { throw 'Flutter clone failed. Existing directories were preserved.' }
}
$actualCommit = git -C $sdkPath rev-parse HEAD
if ($LASTEXITCODE -ne 0 -or $actualCommit -ne $expectedCommit) { throw 'SDK revision does not match the tested Flutter release.' }
& (Join-Path $sdkPath 'bin/flutter.bat') --version
if ($LASTEXITCODE -ne 0) { throw 'Flutter initialization failed.' }
Write-Host 'Use ./tool/flutter.ps1 for project commands. Global Flutter was not changed.'
