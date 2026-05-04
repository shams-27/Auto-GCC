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

# ------------------------------------------------
# Shared spinner function
# ------------------------------------------------
function Show-Spinner {
    param([scriptblock]$Job, [string]$Label)

    $job = Start-Job -ScriptBlock $Job
    $spinner = @('|', '/', '-', '\')
    $i = 0
    $timer = [Diagnostics.Stopwatch]::StartNew()

    while ($job.State -eq 'Running') {
        $elapsed = "{0:mm\:ss}" -f [timespan]::FromSeconds($timer.Elapsed.TotalSeconds)
        $line = "  {0}  {1}  [{2}]" -f $spinner[$i % 4], $Label, $elapsed
        Write-Host ("`r" + $line.PadRight(60)) -NoNewline -ForegroundColor Yellow
        $i++
        Start-Sleep -Milliseconds 200
    }

    $timer.Stop()
    Receive-Job $job -ErrorAction Stop | Out-Null
    Remove-Job $job
    Write-Host ("`r  Done!".PadRight(60)) -ForegroundColor Green
}

# ------------------------------------------------
# Download (custom — needs MB counter)
# ------------------------------------------------
Write-Host "Downloading GCC/G++..." -ForegroundColor Cyan

$job = Start-Job -ScriptBlock {
    param($u, $z)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $u -OutFile $z -UseBasicParsing
} -ArgumentList $Url, $ZipFile

$spinner = @('|', '/', '-', '\')
$i = 0
while ($job.State -eq 'Running') {
    $sizeMB = if (Test-Path $ZipFile) {
        "{0:0.0} MB" -f ((Get-Item $ZipFile).Length / 1MB)
    } else { "0.0 MB" }
    $line = "  {0}  {1} downloaded..." -f $spinner[$i % 4], $sizeMB
    Write-Host ("`r" + $line.PadRight(60)) -NoNewline -ForegroundColor Yellow
    $i++
    Start-Sleep -Milliseconds 200
}

Receive-Job $job -ErrorAction Stop | Out-Null
Remove-Job $job
Write-Host ("`r  Done!".PadRight(60)) -ForegroundColor Green

# ------------------------------------------------
# Extract
# ------------------------------------------------
Write-Host "Extracting..." -ForegroundColor Cyan

Show-Spinner -Label "Extracting files..." -Job {
    param($z, $d)
    $ProgressPreference = 'SilentlyContinue'
    Expand-Archive -Path $z -DestinationPath $d -Force
}

Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue

# ------------------------------------------------
# Add to PATH
# ------------------------------------------------
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
