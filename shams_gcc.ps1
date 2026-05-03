# ================================================
# shams_gcc.ps1 - SHAMS GCC Installer (winlibs)
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

Write-Host "`nDownloading latest GCC/G++ (winlibs)..." -ForegroundColor Cyan

$Url = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile = "$env:TEMP\winlibs.zip"

# Real-time Progress Bar
$ProgressPreference = 'Continue'

function Show-Progress {
    param([long]$BytesReceived, [long]$TotalBytes)
    $percent = [math]::Round(($BytesReceived / $TotalBytes) * 100)
    $bar = "█" * [math]::Floor($percent / 5)
    $spaces = " " * (20 - $bar.Length)
    Write-Host "`rDownloading: [$bar$spaces] $percent% ($([math]::Round($BytesReceived/1MB))MB / $([math]::Round($TotalBytes/1MB))MB) " -NoNewline
}

$WebClient = New-Object System.Net.WebClient
$WebClient.add_DownloadProgressChanged({ Show-Progress $_.BytesReceived $_.TotalBytesToReceive })
$WebClient.add_DownloadFileCompleted({ Write-Host "`nDownload Completed!" -ForegroundColor Green })

$WebClient.DownloadFileAsync([Uri]$Url, $ZipFile)

while ($WebClient.IsBusy) { 
    Start-Sleep -Milliseconds 300 
}

Write-Host "`nExtracting files..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force

Remove-Item $ZipFile -Force

# Add to PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    Write-Host "PATH Updated" -ForegroundColor Green
}

Write-Host @"

╔══════════════════════════════════════════════════════════════╗
║                    INSTALLATION SUCCESSFUL!                  ║
╚══════════════════════════════════════════════════════════════╝
"@ -ForegroundColor Green

Write-Host "GCC Location → $BinPath\gcc.exe" -ForegroundColor Green

Write-Host "`nClose this window and open a NEW PowerShell window." -ForegroundColor Yellow
Write-Host "Test commands:" -ForegroundColor Cyan
Write-Host "   gcc --version" 
Write-Host "   g++ --version" 
Write-Host "`nDone! Happy Coding 💙" -ForegroundColor Magenta
