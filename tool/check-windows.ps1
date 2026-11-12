param([string]$Flutter = (Join-Path $PSScriptRoot 'flutter.ps1'))
$ErrorActionPreference = 'Stop'
$appRoot = Split-Path $PSScriptRoot -Parent
Push-Location $appRoot
try {
    New-Item -ItemType Directory -Force .local/test-results | Out-Null
    $results = @()
    # Some Windows Flutter runners lose a suite connection when several files
    # share one invocation. Each file gets its own process and recorded result.
    $files = @(rg --files test -g '*_test.dart' | Sort-Object)
    if ($LASTEXITCODE -ne 0 -or $files.Count -eq 0) { throw 'No tests found.' }
    foreach ($file in $files) {
        $name = [IO.Path]::GetFileNameWithoutExtension($file)
        & $Flutter test --no-pub --reporter expanded $file *> ".local/test-results/$name.log"
        $code = $LASTEXITCODE
        $results += [PSCustomObject]@{ file=$file; exitCode=$code }
        $results | ConvertTo-Json | Set-Content .local/test-results/summary.json
        Write-Host "$file : $code"
    }
    if (@($results | Where-Object exitCode -ne 0).Count) { exit 1 }
} finally { Pop-Location }
