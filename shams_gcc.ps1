# ================================================
# shams_gcc.ps1 - Robust MSYS2 + GCC/G++ Installer
# Improved version with better feedback
# ================================================

param(
    [switch]$SystemWide = $false
)

$MSYS2Dir = if ($SystemWide) { "C:\msys64" } else { "$env:USERPROFILE\msys64" }
$UCRT64Bin = "$MSYS2Dir\ucrt64\bin"

Write-Host "Starting MSYS2 + GCC/G++ Installation..." -ForegroundColor Cyan

# Install MSYS2
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Installing MSYS2 via winget..." -ForegroundColor Cyan
    winget install --id MSYS2.MSYS2 -e --accept-source-agreements --accept-package-agreements --force
} else {
    Write-Host "Downloading MSYS2 installer..." -ForegroundColor Yellow
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $installer = "$env:TEMP\msys2-installer.exe"
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    Start-Process -FilePath $installer -ArgumentList "--root `"$MSYS2Dir`" --confirm" -Wait
}

$bash = "$MSYS2Dir\usr\bin\bash.exe"

if (!(Test-Path $bash)) {
    Write-Host "MSYS2 installation failed. bash.exe not found." -ForegroundColor Red
    exit 1
}

Write-Host "MSYS2 found. Updating system..." -ForegroundColor Green

# Update MSYS2 with visible output
& $bash -lc "pacman -Syu --noconfirm"
& $bash -lc "pacman -Su --noconfirm"

Write-Host "Installing GCC/G++ and development tools..." -ForegroundColor Cyan

# Main installation with full output
$packages = "mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja " +
            "mingw-w64-ucrt-x86_64-gdb git base-devel mingw-w64-ucrt-x86_64-make"

$result = & $bash -lc "pacman -S --needed --noconfirm $packages"

Write-Host $result -ForegroundColor White

# Check if installation succeeded
if (Test-Path "$UCRT64Bin\gcc.exe") {
    Write-Host "GCC/G++ installed successfully!" -ForegroundColor Green
} else {
    Write-Host "gcc.exe not found. Retrying installation..." -ForegroundColor Yellow
    & $bash -lc "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain"
}

# Add to PATH
$target = if ($SystemWide) { "Machine" } else { "User" }
$path = [Environment]::GetEnvironmentVariable("Path", $target)

if ($path -notlike "*$UCRT64Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$path;$UCRT64Bin", $target)
    Write-Host "Added to PATH: $UCRT64Bin" -ForegroundColor Green
}

Write-Host "`nInstallation Process Completed!" -ForegroundColor Green
Write-Host "GCC Path : $UCRT64Bin\gcc.exe" -ForegroundColor Green

Write-Host "`nNext Steps:" -ForegroundColor Yellow
Write-Host "1. Close this PowerShell window completely."
Write-Host "2. Open a NEW PowerShell window and test:"
Write-Host "   gcc --version" -ForegroundColor Cyan
Write-Host "   g++ --version" -ForegroundColor Cyan

Write-Host "`nYou can also use the 'MSYS2 UCRT64' shortcut from Start Menu." -ForegroundColor Cyan
