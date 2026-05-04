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

$job = Start-Job -ScriptBlock {
    param($u, $z)
    $ProgressPreference = 'SilentlyContinue'
    Invoke-WebRequest -Uri $u -OutFile $z -UseBasicParsing
} -ArgumentList $Url, $ZipFile

# Hide cursor via Win32 API (works in all PS versions and execution modes)
$code = @"
using System;
using System.Runtime.InteropServices;
public class ConsoleCursor {
    [DllImport("kernel32.dll")]
    static extern IntPtr GetStdHandle(int h);
    [DllImport("kernel32.dll")]
    static extern bool GetConsoleCursorInfo(IntPtr h, out CONSOLE_CURSOR_INFO i);
    [DllImport("kernel32.dll")]
    static extern bool SetConsoleCursorInfo(IntPtr h, ref CONSOLE_CURSOR_INFO i);
    public struct CONSOLE_CURSOR_INFO { public int Size; public bool Visible; }
    public static void Hide() {
        var h = GetStdHandle(-11);
        CONSOLE_CURSOR_INFO i;
        GetConsoleCursorInfo(h, out i);
        i.Visible = false;
        SetConsoleCursorInfo(h, ref i);
    }
    public static void Show() {
        var h = GetStdHandle(-11);
        CONSOLE_CURSOR_INFO i;
        GetConsoleCursorInfo(h, out i);
        i.Visible = true;
        SetConsoleCursorInfo(h, ref i);
    }
}
"@
Add-Type -TypeDefinition $code
[ConsoleCursor]::Hide()

$spinner = @('|', '/', '-', '\')
$i = 0
while ($job.State -eq 'Running') {
    $sizeMB = if (Test-Path $ZipFile) {
        "{0:0.0} MB" -f ((Get-Item $ZipFile).Length / 1MB)
    } else { "0.0 MB" }

    Write-Host ("`r  {0}  {1} downloaded..." -f $spinner[$i % 4], $sizeMB) -NoNewline -ForegroundColor Yellow
    $i++
    Start-Sleep -Milliseconds 200
}

[ConsoleCursor]::Show()

Receive-Job $job -ErrorAction Stop | Out-Null
Remove-Job $job

Write-Host "`r  Done!                              " -ForegroundColor Green

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
