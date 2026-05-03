# ================================================
# shams_gcc.ps1 - SHAMS GCC Installer (winlibs)
# Simple | Fast | Reliable
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
║                   An Automatic Install Solution for GCC / G++                  ║
║                                                                                ║
╚════════════════════════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

$InstallDir = "$env:USERPROFILE\mingw64"
$BinPath = "$InstallDir\mingw64\bin"

Write-Host "Downloading latest GCC/G++ (winlibs)..." -ForegroundColor Cyan

# Latest winlibs (UCRT64, POSIX)
$Url = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile = "$env:TEMP\winlibs.zip"

# Disable default progress bar
$ProgressPreference = 'SilentlyContinue'

Write-Host "Downloading GCC/G++ " -NoNewline
$WebClient = New-Object System.Net.WebClient
$WebClient.DownloadFile($Url, $ZipFile)

# Simple animated progress
for ($i = 1; $i -le 20; $i++) {
    Write-Host "." -NoNewline -ForegroundColor Yellow
    Start-Sleep -Milliseconds 80
}
Write-Host " Done!" -ForegroundColor Green

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force

# Clean up
Remove-Item $ZipFile -Force

# Add to PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    Write-Host "Added to PATH" -ForegroundColor Green
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                   INSTALLATION SUCCESSFUL!                   ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "GCC Location: $BinPath\gcc.exe" -ForegroundColor Green

Write-Host "`nClose this window and open a NEW PowerShell, then test:" -ForegroundColor Yellow
Write-Host "   gcc --version" -ForegroundColor Cyan
Write-Host "   g++ --version" -ForegroundColor Cyan
Write-Host "`nDone! Happy Coding 💙" -ForegroundColor Magenta
