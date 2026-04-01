# src\Tasks\Client\Set-DesktopWallpaper.ps1
$ErrorActionPreference = "Stop"

# Locate source image: src\Tasks\Client\ -> src\MISC\Background\
$srcRoot  = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$imageSrc = Join-Path $srcRoot "MISC\Background\CITADesktopBackground.png"

if (-not (Test-Path $imageSrc)) {
    throw "Background image not found: $imageSrc"
}

# Copy to a permanent local path so the wallpaper path is stable even when the repo is unmounted
$destDir  = Join-Path $env:APPDATA "CITA"
if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
$imageDest = Join-Path $destDir "CITADesktopBackground.png"
Copy-Item -Path $imageSrc -Destination $imageDest -Force

# Disable Windows Spotlight on the desktop and stop rotating content
$cdmKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
if (Test-Path $cdmKey) {
    Set-ItemProperty -Path $cdmKey -Name "RotatingLockScreenEnabled"         -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $cdmKey -Name "SubscribedContent-338388Enabled"   -Value 0 -Type DWord -Force
}

# Set background type to Picture (0) — overrides Spotlight (3) / Slideshow (2)
$wallpapersKey = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Wallpapers"
if (-not (Test-Path $wallpapersKey)) { New-Item -Path $wallpapersKey -Force | Out-Null }
Set-ItemProperty -Path $wallpapersKey -Name "BackgroundType" -Value 0 -Type DWord -Force

# Apply wallpaper live via Win32 SystemParametersInfo
Add-Type -TypeDefinition @"
using System.Runtime.InteropServices;
public class WallpaperSetter {
    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
}
"@

$result = [WallpaperSetter]::SystemParametersInfo(0x0014, 0, $imageDest, 0x01 -bor 0x02)

Write-Host ""
if ($result -ne 0) {
    Write-Host "Desktop wallpaper applied." -ForegroundColor Green
} else {
    Write-Host "Warning: wallpaper API returned 0 — changes saved to registry but may require sign-out/sign-in." -ForegroundColor Yellow
}
Write-Host "Source:  $imageSrc"
Write-Host "Stored:  $imageDest"
Write-Host ""
Write-Host "Windows Spotlight has been disabled for the desktop." -ForegroundColor Cyan
Write-Host "Note: a sign-out/sign-in may be needed for registry changes to fully take effect." -ForegroundColor DarkGray
