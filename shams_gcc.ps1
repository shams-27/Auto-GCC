# ================================================
# shams_gcc.ps1 - Full Reliable MSYS2 + GCC Installer
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

Write-Host "Starting Fully Automatic Installation..." -ForegroundColor Cyan

# Automatic MSYS2 Installation
if (!(Test-Path $bash)) {
    Write-Host "Downloading MSYS2 installer..." -ForegroundColor Yellow
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $installer = "$env:TEMP\msys2-installer.exe"
    
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing

    Write-Host "Installing MSYS2 automatically (silent mode)..." -ForegroundColor Yellow
    # Silent installation with no GUI prompts
    Start-Process -FilePath $installer -ArgumentList "--root `"$MSYS2Dir`" --confirm --silent" -Wait -NoNewWindow
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
    "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain base-devel git",
    "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-gdb"
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
    Write-Host "GCC not found. Try running the script again or use MSYS2 UCRT64 terminal." -ForegroundColor Yellow
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
