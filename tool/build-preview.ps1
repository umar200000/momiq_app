param([ValidateRange(1,65535)][int]$Port = 8081)
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
$previewUrl = "http://127.0.0.1:$Port"
$health = Invoke-RestMethod "$previewUrl/api/health" -TimeoutSec 5
if ($health.mode -ne 'local' -or -not $health.instanceId) {
    throw 'Preview requires the running local Momiq instance; build was not started.'
}
$previewConfig = Get-Content (Join-Path $appRoot 'config/local.json') -Raw | ConvertFrom-Json
$previewConfig.MOMIQ_API_URL = "$previewUrl/api"
$previewConfig.MOMIQ_ENV = 'local'
$configPath = Join-Path $appRoot '.local/preview-build-config.json'
New-Item -ItemType Directory -Force (Split-Path $configPath -Parent) | Out-Null
$previewConfig | ConvertTo-Json | Set-Content -LiteralPath $configPath -Encoding utf8
Write-Host "Building Android x64 preview for $previewUrl/api"
Push-Location $appRoot
try {
    & ./tool/flutter.ps1 build apk --debug --target-platform android-x64 "--dart-define-from-file=$configPath"
    if ($LASTEXITCODE -ne 0) { throw 'Preview build failed; do not install an older APK.' }
    $apk = Join-Path $appRoot 'build/app/outputs/flutter-apk/app-debug.apk'
    @{apiUrl="$previewUrl/api";instanceId=$health.instanceId;sha256=(Get-FileHash -LiteralPath $apk -Algorithm SHA256).Hash} |
        ConvertTo-Json | Set-Content -LiteralPath (Join-Path $appRoot '.local/preview-apk.json') -Encoding utf8
} finally { Pop-Location }
