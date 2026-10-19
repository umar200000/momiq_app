# Run after: flutter test tool/generate_app_icons.dart
# Apple app icons must use RGB PNGs without an alpha channel.
Add-Type -AssemblyName System.Drawing
$projectRoot = Split-Path $PSScriptRoot -Parent
$iconDirectory = Join-Path $projectRoot 'ios/Runner/Assets.xcassets/AppIcon.appiconset'
foreach ($file in Get-ChildItem -LiteralPath $iconDirectory -Filter '*.png') {
    $source = [System.Drawing.Image]::FromFile($file.FullName)
    $rgb = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format24bppRgb)
    $graphics = [System.Drawing.Graphics]::FromImage($rgb)
    $graphics.DrawImageUnscaled($source, 0, 0)
    $graphics.Dispose()
    $source.Dispose()
    $rgb.Save($file.FullName, [System.Drawing.Imaging.ImageFormat]::Png)
    $rgb.Dispose()
    $header = [System.IO.File]::ReadAllBytes($file.FullName)
    if ($header[25] -ne 2) { throw "Icon is not RGB: $($file.Name)" }
}
Write-Output 'iOS icons verified: RGB PNGs without alpha.'
