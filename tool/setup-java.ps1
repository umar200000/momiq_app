$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
# Official Adoptium API metadata, recorded 2026-10-28; update URL and hash together.
$archiveUrl = 'https://github.com/adoptium/temurin21-binaries/releases/download/jdk-21.0.12.1%2B1/OpenJDK21U-jdk_x64_windows_hotspot_21.0.12.1_1.zip'
$expectedHash = 'f9d6e191ab098c0d416e7d588a24420a8621cd2f4720dab2459b8b7b2d2d8b4e'
$runtime = Join-Path $appRoot '.local/toolchains/temurin-21.0.12.1-1'
$javaPath = Join-Path $runtime 'jdk-21.0.12.1+1'
if (-not (Test-Path -LiteralPath (Join-Path $javaPath 'bin/java.exe'))) {
    $archive = Join-Path $appRoot '.local/toolchains/temurin-21.0.12.1-1.zip'
    New-Item -ItemType Directory -Force -Path (Split-Path $archive -Parent) | Out-Null
    if (-not (Test-Path -LiteralPath $archive)) {
        $download = "$archive.$([guid]::NewGuid().ToString('N')).download"
        & curl.exe --fail --location --retry 2 --retry-delay 2 --connect-timeout 15 --max-time 240 --silent --show-error --output $download $archiveUrl
        if ($LASTEXITCODE -ne 0) { throw "JDK download failed; partial file preserved at $download" }
        if ((Get-FileHash -LiteralPath $download -Algorithm SHA256).Hash -ne $expectedHash) { throw 'Downloaded JDK checksum mismatch; file preserved.' }
        Move-Item -LiteralPath $download -Destination $archive
    }
    if ((Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash -ne $expectedHash) {
        throw 'JDK checksum mismatch; archive preserved. No code was executed.'
    }
    if (Test-Path -LiteralPath $runtime) { throw 'Incomplete JDK directory exists; preserved for inspection.' }
    Expand-Archive -LiteralPath $archive -DestinationPath $runtime
}
& (Join-Path $javaPath 'bin/java.exe') -version
if ($LASTEXITCODE -ne 0) { throw 'JDK verification failed.' }
Write-Host 'Project JDK installed. The Flutter wrapper selects it for the Gradle daemon; global Java/Flutter settings were not changed.'
