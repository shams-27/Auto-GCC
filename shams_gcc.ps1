# ================================================
# shams_gcc.ps1 - Simple GCC Installer
# ================================================

# Auto-elevate to Administrator if not already running as one
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting as Administrator..." -ForegroundColor Yellow
    $scriptUrl = "https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1"
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -Command `"irm '$scriptUrl' | iex`""
    exit
}

Write-Host "Auto GCC Installer" -ForegroundColor Cyan
Write-Host "====================================`n" -ForegroundColor Cyan

$InstallDir = "C:\mingw64"
$BinPath = "$InstallDir\mingw64\bin"

Write-Host "Downloading GCC/G++..." -ForegroundColor Cyan

$Url = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile = "$env:TEMP\winlibs.zip"

$ProgressPreference = 'SilentlyContinue'  # Suppress default byte-based progress

try {
    $webClient = New-Object System.Net.WebClient
    $webClient.add_DownloadProgressChanged({
        param($s, $e)
        $downloadedMB = [math]::Round($e.BytesReceived / 1MB, 1)
        $totalMB      = [math]::Round($e.TotalBytesToReceive / 1MB, 1)
        $pct          = if ($e.TotalBytesToReceive -gt 0) { $e.ProgressPercentage } else { -1 }
        if ($pct -ge 0) {
            Write-Progress -Activity "Downloading GCC/G++..." `
                           -Status "$downloadedMB MB / $totalMB MB" `
                           -PercentComplete $pct
        } else {
            Write-Progress -Activity "Downloading GCC/G++..." -Status "$downloadedMB MB downloaded"
        }
    })
    $task = $webClient.DownloadFileTaskAsync($Url, $ZipFile)
    $task.Wait()
    Write-Progress -Activity "Downloading GCC/G++..." -Completed
} finally {
    $webClient.Dispose()
    $ProgressPreference = 'Continue'
}

Write-Host "Extracting..." -ForegroundColor Cyan
Expand-Archive -Path $ZipFile -DestinationPath $InstallDir -Force

Remove-Item $ZipFile -Force

# Add to PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    Write-Host "PATH Updated" -ForegroundColor Green
}

Write-Host "`nInstallation Completed!" -ForegroundColor Green
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green

Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version" 
Write-Host "   g++ --version"
