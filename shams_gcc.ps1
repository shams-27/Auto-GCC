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

Write-Host "Starting Full MSYS2 + GCC Installation..." -ForegroundColor Cyan

# Install MSYS2 if not present
if (!(Test-Path $bash)) {
    Write-Host "Downloading MSYS2 installer..." -ForegroundColor Cyan
    $url = "https://github.com/msys2/msys2-installer/releases/latest/download/msys2-x86_64-latest.exe"
    $installer = "$env:TEMP\msys2-installer.exe"
    Invoke-WebRequest -Uri $url -OutFile $installer -UseBasicParsing
    
    Write-Host "Running installer (this may take a minute)..." -ForegroundColor Yellow
    Start-Process -FilePath $installer -ArgumentList "--root `"$MSYS2Dir`" --confirm" -Wait
}

if (!(Test-Path $bash)) {
    Write-Host "MSYS2 installation failed." -ForegroundColor Red
    exit 1
}

Write-Host "MSYS2 is ready. Now installing toolchain..." -ForegroundColor Green

# Run full installation with multiple attempts and visible output
$commands = @(
    "pacman -Syu --noconfirm",
    "pacman -Su --noconfirm",
    "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain",
    "pacman -S --needed --noconfirm base-devel git mingw-w64-ucrt-x86_64-cmake mingw-w64-ucrt-x86_64-ninja mingw-w64-ucrt-x86_64-gdb"
)

foreach ($cmd in $commands) {
    Write-Host "Running: $cmd" -ForegroundColor Cyan
    $output = & $bash -lc $cmd 2>&1
    Write-Host $output -ForegroundColor White
}

# Final check
if (Test-Path "$UCRT64Bin\gcc.exe") {
    Write-Host "`nSUCCESS! GCC and G++ are installed." -ForegroundColor Green
    Write-Host "Files found in: $UCRT64Bin" -ForegroundColor Green
} else {
    Write-Host "`nStill no gcc.exe. Trying one more time..." -ForegroundColor Yellow
    & $bash -lc "pacman -S --needed --noconfirm mingw-w64-ucrt-x86_64-toolchain"
}

# Add to PATH
$path = [Environment]::GetEnvironmentVariable("Path","User")
if ($path -notlike "*$UCRT64Bin*") {
    [Environment]::SetEnvironmentVariable("Path","$path;$UCRT64Bin","User")
    Write-Host "PATH updated" -ForegroundColor Green
}

Write-Host "`nScript finished." -ForegroundColor Green
Write-Host "Please close this window and open a NEW PowerShell to test:" -ForegroundColor Yellow
Write-Host "   gcc --version" -ForegroundColor Cyan
Write-Host "   g++ --version" -ForegroundColor Cyan
