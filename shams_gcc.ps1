# ================================================
# shams_gcc.ps1 - Simple GCC Installer
# ================================================

# Auto-elevate to Administrator if not already running as one
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $shellExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Start-Process $shellExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    exit
}

# ------------------------------------------------
# Progress bar helpers  
# ------------------------------------------------
$script:_pbRow = -1   # console row where the two-line bar lives

function Show-ProgressBar {
    param(
        [string]$Status,
        [int]   $Percent   
    )

    $winWidth = $Host.UI.RawUI.WindowSize.Width
    $barInner = [Math]::Max(10, $winWidth - 3)   

    $filled = if ($Percent -lt 0) {
        $barInner
    } else {
        [Math]::Min($barInner, [int](($barInner * $Percent) / 100))
    }
    $empty = $barInner - $filled

    # Reserve two lines on first call
    if ($script:_pbRow -lt 0) {
        Write-Host ""   
        Write-Host ""   
        $script:_pbRow = $Host.UI.RawUI.CursorPosition.Y - 2
    }

    # --- line 1: status text ---
    [Console]::SetCursorPosition(0, $script:_pbRow)
    $padded = $Status.PadRight($winWidth - 1).Substring(0, $winWidth - 1)
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::Cyan
    [Console]::Write($padded)

    # --- line 2: [ ooo...   ] ---
    [Console]::SetCursorPosition(0, $script:_pbRow + 1)
    [Console]::Write('[' + ('0' * $filled) + (' ' * $empty) + ']')
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::White   # restore default
}

function Clear-ProgressBar {
    if ($script:_pbRow -lt 0) { return }
    $winWidth = $Host.UI.RawUI.WindowSize.Width
    $blank    = ' ' * ($winWidth - 1)
    [Console]::SetCursorPosition(0, $script:_pbRow)
    [Console]::WriteLine($blank)
    [Console]::WriteLine($blank)
    [Console]::SetCursorPosition(0, $script:_pbRow)
    $script:_pbRow = -1
}

# ------------------------------------------------

Write-Host ""
$lines = @(
    ' _______          _________ _______    _______  _______  _______ ',
    '(  ___  )|\     /|\__   __/(  ___  )  (  ____ \(  ____ \(  ____ \',
    '| (   ) || )   ( |   ) (   | (   ) |  | (    \/| (    \/| (    \/',
    '| (___) || |   | |   | |   | |   | |  | |      | |      | |      ',
    '|  ___  || |   | |   | |   | |   | |  | | ____ | |      | |      ',
    '| (   ) || |   | |   | |   | |   | |  | | \_  )| |      | |      ',
    '| )   ( || (___) |   | |   | (___) |  | (___) || (____/\| (____/\',
    '|/     \|(_______)   )_(   (_______)  (_______)(_______/(_______/'
)

$split = 38

foreach ($line in $lines) {
    [Console]::ForegroundColor = [ConsoleColor]::Blue
    [Console]::Write($line.Substring(0, $split))
    [Console]::ForegroundColor = [ConsoleColor]::DarkYellow
    [Console]::WriteLine($line.Substring($split))
}

[Console]::ResetColor()
Write-Host ""

$InstallDir = "C:\mingw64"
$BinPath    = "$InstallDir\mingw64\bin"
$Url        = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile    = "$env:TEMP\winlibs.zip"

Write-Host "Downloading..." -ForegroundColor Cyan

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$request = [System.Net.HttpWebRequest]::Create($Url)
$request.UserAgent = 'shams_gcc-installer/1.0'
$request.AllowAutoRedirect = $true
try {
    $response = $request.GetResponse()
    try {
        $totalBytes = [int64]$response.ContentLength
        $readStream = $response.GetResponseStream()
        $fileStream = [System.IO.File]::Create($ZipFile)
        try {
            $buffer    = New-Object byte[] (1MB)
            $totalRead = 0
            $read      = 0
            $downloadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (($read = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                $elapsedSeconds = [math]::Max(0.001, $downloadStopwatch.Elapsed.TotalSeconds)
                $speedMBps      = ($totalRead / 1MB) / $elapsedSeconds
                if ($totalBytes -gt 0) {
                    $pct     = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                    $doneMB  = '{0:N2}' -f ($totalRead / 1MB)
                    $totalMB = '{0:N2}' -f ($totalBytes / 1MB)
                    Show-ProgressBar -Status "Downloaded $doneMB MB of $totalMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent $pct
                } else {
                    $doneMB = '{0:N2}' -f ($totalRead / 1MB)
                    Show-ProgressBar -Status "Downloaded $doneMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent -1
                }
            }
        } finally {
            $fileStream.Dispose()
            $readStream.Dispose()
        }
    } finally {
        $response.Dispose()
    }
} finally {
    Clear-ProgressBar
}

Write-Host "  Download finished." -ForegroundColor Green

Write-Host "`nExtracting..." -ForegroundColor Cyan
Add-Type -AssemblyName System.IO.Compression.FileSystem
$archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
try {
    $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    $n = $fileEntries.Count
    $i = 0
    foreach ($entry in $fileEntries) {
        $i++
        $relative = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
        $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($InstallDir, $relative))
        $installRoot = [System.IO.Path]::GetFullPath($InstallDir)
        if (-not $targetPath.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
            throw "Refusing to extract outside install dir: $targetPath"
        }
        $destDir = [System.IO.Path]::GetDirectoryName($targetPath)
        if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
        $pct = if ($n -gt 0) { [math]::Min(100, [int](100 * $i / $n)) } else { 100 }
        Show-ProgressBar -Status "Extracting file $i of $n ($pct%)" -Percent $pct
    }
} finally {
    $archive.Dispose()
    Clear-ProgressBar
}

Write-Host "  Extraction finished." -ForegroundColor Green

if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# Add to PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    Write-Host ""
    $pathSteps = 22
    $applyAt   = [math]::Ceiling($pathSteps / 2)
    $applied   = $false
    for ($s = 1; $s -le $pathSteps; $s++) {
        if (-not $applied -and $s -ge $applyAt) {
            [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
            $applied = $true
        }
        $pct = [math]::Min(100, [int](100 * $s / $pathSteps))
        Show-ProgressBar -Status "Updating user PATH ($pct%)" -Percent $pct
        Start-Sleep -Milliseconds 38
    }
    if (-not $applied) {
        [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    }
    Clear-ProgressBar
    Write-Host "PATH Updated" -ForegroundColor Green
}

Write-Host "Installation Completed!" -ForegroundColor Green
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green
Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version"
Write-Host "   g++ --version`n"
