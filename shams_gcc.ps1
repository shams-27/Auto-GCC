# ================================================
# shams_gcc.ps1 - MSYS2 + GCC/G++ Installer
# One-click full C/C++ development setup for Windows
# ================================================

param(
    [switch]$SystemWide = $false
)

$MSYS2Dir = if ($SystemWide) { "C:\msys64" } else { "$env:USERPROFILE\msys64" }
$UCRT64Bin = "$MSYS2Dir\ucrt64\bin"

Write-Host "Installing MSYS2 + GCC/G++ (Full UCRT64 Environment)..." -ForegroundColor Cyan

# Install MSYS2
if (Get-Command winget -ErrorAction SilentlyContinue) {
    Write-Host "Installing MSYS2 via winget..." -ForegroundColor Cyan
    winget install --id MSYS2.MSYS2 -e --silent --accept-source-agreements --accept-package-agreements --force
} else {
    Write-Host "Downloading MSYS2 installer..." -ForegroundColor Yellow
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $installer = "$env:TEMP\msys2-installer.exe"
    Invoke-WebRequest -Uri $url -OutFile $installer
    Start-Process -FilePath $installer -ArgumentList "--root $MSYS2Dir --confirm" -Wait
}

$bash = "$MSYS2Dir\usr\bin\bash.exe"

# Update system
Write-Host "Updating MSYS2..." -ForegroundColor Cyan
& $bash -lc "pacman -Syu --noconfirm" | Out-Null
& $bash -lc "pacman -Su --noconfirm" | Out-Null

# Install GCC + essential tools
Write-Host "Installing GCC, G++, CMake, GDB, Ninja, Git..." -ForegroundColor Cyan
$packages = "mingw-w64-ucrt-x86_64-toolchain mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja " +
            "mingw-w64-ucrt-x86_64-gdb git base-devel mingw-w64-ucrt-x86_64-make"

& $bash -lc "pacman -S --needed --noconfirm $packages"

# Add to PATH
$target = if ($SystemWide) { "Machine" } else { "User" }
$path = [Environment]::GetEnvironmentVariable("Path", $target)

if ($path -notlike "*$UCRT64Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$path;$UCRT64Bin", $target)
    Write-Host "Added to PATH successfully" -ForegroundColor Green
}

Write-Host "`n Installation Completed Successfully!" -ForegroundColor Green
Write-Host "GCC Location : $UCRT64Bin\gcc.exe" -ForegroundColor Green
Write-Host "G++ Location : $UCRT64Bin\g++.exe" -ForegroundColor Green

# Test
Write-Host "`nTesting installation..." -ForegroundColor Cyan
& "$UCRT64Bin\gcc.exe" --version | Select-Object -First 1
& "$UCRT64Bin\g++.exe" --version | Select-Object -First 1

Write-Host "`n Don't forget to restart your PowerShell / VS Code / Terminal!" -ForegroundColor Yellow