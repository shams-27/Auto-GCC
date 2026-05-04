# ================================================
# shams_gcc.ps1 - Simple GCC Installer
# ================================================

# Auto-elevate to Administrator if not already running as one
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Restarting as Administrator..." -ForegroundColor Yellow
    $tempScript = "$env:TEMP\shams_gcc_temp.ps1"
    $scriptUrl  = "https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1"
    Invoke-RestMethod -Uri $scriptUrl -OutFile $tempScript
    Start-Process powershell -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
    exit
}

Write-Host "Auto GCC Installer" -ForegroundColor Cyan
Write-Host "====================================`n" -ForegroundColor Cyan

$InstallDir = "C:\mingw64"
$BinPath    = "$InstallDir\mingw64\bin"
$Url        = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile    = "$env:TEMP\winlibs.zip"

Write-Host "Downloading GCC/G++..." -ForegroundColor Cyan

$ProgressPreference = 'SilentlyContinue'

$webClient = New-Object System.Net.WebClient
$task = $webClient.DownloadFileTaskAsync($Url, $ZipFile)

while (-not $task.IsCompleted) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $ZipFile) {
        $downloadedMB = [math]::Round((Get-Item $ZipFile).Length / 1MB, 1)
        Write-Host "`r  $downloadedMB MB downloaded..." -NoNewline -ForegroundColor Gray
    }
}

$webClient.Dispose()
$ProgressPreference = 'Continue'

if ($task.IsFaulted) { throw $task.Exception.InnerException }

Write-Host "`r  Download complete!              " -ForegroundColor Green

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
