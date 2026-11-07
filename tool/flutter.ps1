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
$savedGradleOptions = $env:GRADLE_OPTS
$projectJava = if ($env:MOMIQ_JAVA_HOME) { $env:MOMIQ_JAVA_HOME } else { Join-Path $appRoot '.local/toolchains/temurin-21.0.12.1-1/jdk-21.0.12.1+1' }
$needsJava = ($args.Count -gt 0 -and $args[0] -in @('build','run','drive'))
if ($needsJava) {
    $javaBinary = Join-Path $projectJava 'bin/java.exe'
    if (-not (Test-Path -LiteralPath $javaBinary)) { throw 'Run ./tool/setup-java.ps1, or set MOMIQ_JAVA_HOME to a JDK 21 installation.' }
    $javaVersion = (& $javaBinary -version 2>&1 | Out-String)
    if ($LASTEXITCODE -ne 0 -or $javaVersion -notmatch 'version "21[.\"]') { throw 'Project builds require JDK 21, matching CI.' }
}
$savedTemp = $env:TEMP
$savedTmp = $env:TMP
try {
    $env:GRADLE_USER_HOME = Join-Path $appRoot '.local/gradle'
    if ($needsJava) {
        # Flutter may launch the wrapper with Android Studio's bundled Java.
        # This project-scoped system property selects the actual build JVM.
        $env:GRADLE_OPTS = "$savedGradleOptions `"-Dorg.gradle.java.home=$projectJava`""
    }
    $env:TEMP = Join-Path $appRoot '.local/tmp'
    $env:TMP = $env:TEMP
    New-Item -ItemType Directory -Force -Path $env:GRADLE_USER_HOME,$env:TEMP | Out-Null
    & $executable @args
    $result = $LASTEXITCODE
} finally {
    $env:GRADLE_USER_HOME = $savedGradleHome
    $env:GRADLE_OPTS = $savedGradleOptions
    $env:TEMP = $savedTemp
    $env:TMP = $savedTmp
}
exit $result
