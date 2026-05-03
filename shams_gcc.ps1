# ================================================
# shams_gcc.ps1 - SHAMS GCC Installer
# ================================================

Write-Host @"
╔════════════════════════════════════════════════════════════════════════════════╗
║                                                                                ║
║   ███████╗██╗  ██╗ █████╗ ███╗   ███╗███████╗    ██████╗   ██████╗  ██████╗    ║
║   ██╔════╝██║  ██║██╔══██╗████╗ ████║██╔════╝    ██╔════╝  ██╔════╝ ██╔════╝   ║
║   ███████╗███████║███████║██╔████╔██║███████╗    ██║  ███╗ ██║  ███╗██║  ███╗  ║
║   ╚════██║██╔══██║██╔══██║██║╚██╔╝██║╚════██║    ██║   ██║ ██║   ██║██║   ██║  ║
║   ███████║██║  ██║██║  ██║██║ ╚═╝ ██║███████║    ╚██████╔╝ ╚██████╔╝╚██████╔╝  ║
║   ╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝╚═╝     ╚═╝╚══════╝     ╚═════╝   ╚═════╝  ╚═════╝   ║
║                                                                                ║
║                    An Automatic Install System for GCC / G++                   ║
║                                                                                ║
╚════════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

$MSYS2Dir = "C:\msys64"
$UCRT64Bin = "$MSYS2Dir\ucrt64\bin"
$bash = "$MSYS2Dir\usr\bin\bash.exe"
$installerPath = "$env:TEMP\msys2-installer.exe"   # ← This was missing

Write-Host "Starting Fully Automatic Installation..." -ForegroundColor Cyan

# Clean old installer
if (Test-Path $installerPath) { 
    Remove-Item $installerPath -Force -ErrorAction SilentlyContinue 
}

# Automatic MSYS2 Installation
if (!(Test-Path $bash)) {
    Write-Host "Downloading MSYS2 installer..." -ForegroundColor Yellow
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $installer = $installerPath   # ← Fixed: Use consistent variable
    
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

    Write-Host "Installing MSYS2 automatically..." -ForegroundColor Yellow
    Start-Process -FilePath $installer -ArgumentList "--root `"$MSYS2Dir`" --confirm" -Wait -NoNewWindow
    Start-Sleep -Seconds 5
}

if (!(Test-Path $bash)) {
    Write-Host "Silent install failed. Trying alternative..." -ForegroundColor Yellow
    Start-Process -FilePath $installerPath -ArgumentList "--root `"$MSYS2Dir`" --confirm" -Wait -NoNewWindow
}

if (!(Test-Path $bash)) {
    Write-Host "Failed to install MSYS2 automatically." -ForegroundColor Red
    Write-Host "Please install MSYS2 manually from: https://www.msys2.org" -ForegroundColor Yellow
    exit 1
}

Write-Host "MSYS2 installed successfully." -ForegroundColor Green

# Install GCC Toolchain
Write-Host "Installing GCC, G++, and development tools..." -ForegroundColor Cyan

$commands = @(
    "pacman -Syu --noconfirm",
    "pacman -Su --noconfirm",
    "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain base-devel git"
)

foreach ($cmd in $commands) {
    Write-Host "Running: $cmd" -ForegroundColor Magenta
    & $bash -lc $cmd
}

# Final Check
if (Test-Path "$UCRT64Bin\gcc.exe") {
    Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║           GCC INSTALLATION COMPLETED SUCCESSFULLY!           ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green
    Write-Host "GCC Path → $UCRT64Bin\gcc.exe" -ForegroundColor Green
} else {
    Write-Host "GCC not found. Try running again or use MSYS2 UCRT64 terminal." -ForegroundColor Yellow
}

# Update PATH
$path = [Environment]::GetEnvironmentVariable("Path","User")
if ($path -notlike "*$UCRT64Bin*") {
    [Environment]::SetEnvironmentVariable("Path", "$path;$UCRT64Bin", "User")
    Write-Host "PATH Updated Successfully" -ForegroundColor Green
}

Write-Host "`nPlease CLOSE this window and open a NEW PowerShell window." -ForegroundColor Yellow
Write-Host "Then test with:" -ForegroundColor Cyan
Write-Host "   gcc --version" 
Write-Host "   g++ --version" 
Write-Host "`nMade by Shams 💙" -ForegroundColor Magenta
