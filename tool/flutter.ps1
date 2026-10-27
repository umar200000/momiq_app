$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$version = (Get-Content (Join-Path $appRoot '.flutter-version') -Raw).Trim()
$sdkPath = if ($env:MOMIQ_FLUTTER_SDK) { $env:MOMIQ_FLUTTER_SDK } else { Join-Path $appRoot ".local/toolchains/flutter-$version" }
$executable = Join-Path $sdkPath 'bin/flutter.bat'
if (-not (Test-Path -LiteralPath $executable)) { throw 'Run ./tool/setup-flutter.ps1 first, or set MOMIQ_FLUTTER_SDK to the pinned SDK.' }
$metadata = Join-Path $sdkPath 'bin/cache/flutter.version.json'
if (-not (Test-Path -LiteralPath $metadata)) { & $executable --version; if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE } }
if ((Get-Content $metadata -Raw | ConvertFrom-Json).frameworkVersion -ne $version) { throw "Expected Flutter $version; SDK path points to another version." }
$savedGradleHome = $env:GRADLE_USER_HOME
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
try {
    $env:GRADLE_USER_HOME = Join-Path $appRoot '.local/gradle'
    $env:TEMP = Join-Path $appRoot '.local/tmp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:GRADLE_USER_HOME,$env:TEMP | Out-Null
    & $executable @args
    $result = $LASTEXITCODE
} finally {
    $env:GRADLE_USER_HOME = $savedGradleHome
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
exit $result
