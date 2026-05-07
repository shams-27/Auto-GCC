# ===================================================
# shams_gcc.ps1 - An Auto GCC Solution 
# ===================================================

Clear-Host

# ================================================
# Auto-elevate to Administrator
# ================================================
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $shellExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Start-Process $shellExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

# ================================================
# Progress bar helpers
# ================================================
$script:_pbRow = -1

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
    if ($script:_pbRow -lt 0) {
        $script:_pbRow = $Host.UI.RawUI.CursorPosition.Y
        Write-Host ""
        Write-Host ""
    }
    [Console]::SetCursorPosition(0, $script:_pbRow)
    $padded = $Status.PadRight($winWidth - 1).Substring(0, $winWidth - 1)
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::Cyan
    [Console]::Write($padded)
    [Console]::SetCursorPosition(0, $script:_pbRow + 1)
    [Console]::Write('[' + ('0' * $filled) + (' ' * $empty) + ']')
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::White
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

# ================================================
# Banner
# ================================================
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

# ================================================
# Check if GCC is already installed
# ================================================
$existingGcc = Get-Command gcc -ErrorAction SilentlyContinue
if ($existingGcc) {
    $gccDir = Split-Path -Path $existingGcc.Path
    Write-Host "GCC is already available on this system." -ForegroundColor Green
    Write-Host "Found directory: $gccDir" -ForegroundColor Cyan
    Write-Host "Skipping installation process.`n" -ForegroundColor Yellow
    return
}

# ================================================
# Config
# ================================================
$InstallDir   = "C:\mingw64"
$BinPath      = "$InstallDir\mingw64\bin"
$Url          = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
# SHA-256 of the official winlibs ZIP
$ExpectedHash = "325771F545E89F62C0E1FAFDBF0066CC49E3321AECA7B704C8D065E97A72F2FB"
$MaxRetries   = 3
$ZipFile      = "$env:TEMP\winlibs.zip"
$Aria2Exe     = "$env:TEMP\aria2c.exe"
$Aria2Zip     = "$env:TEMP\aria2.zip"
$Aria2Url     = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$totalSw     = [System.Diagnostics.Stopwatch]::StartNew()   # FIX 6: track total elapsed time

# ================================================
# Download + verify loop (auto-retries up to $MaxRetries)
# ================================================
for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

if ($attempt -gt 1) {
    Write-Host "`nRetrying... (attempt $attempt of $MaxRetries)" -ForegroundColor Yellow
}

$downloaded = $false

# ================================================
# STRATEGY 1: aria2c — 16 parallel connections
# ================================================

# Print "Preparing..." before aria2c fetch so there's no silent gap
Write-Host "Preparing download..." -ForegroundColor Cyan

# Fetch aria2c itself if not already cached
if (-not (Test-Path $Aria2Exe)) {
    Write-Host "  Fetching aria2c..." -ForegroundColor DarkGray
    try {
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile($Aria2Url, $Aria2Zip)
        $wc.Dispose()

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $az = [System.IO.Compression.ZipFile]::OpenRead($Aria2Zip)
        try {
            $exeEntry = $az.Entries | Where-Object { $_.Name -eq 'aria2c.exe' } | Select-Object -First 1
            if ($exeEntry) {
                [System.IO.Compression.ZipFileExtensions]::ExtractToFile($exeEntry, $Aria2Exe, $true)
            }
        } finally { $az.Dispose() }
        Remove-Item $Aria2Zip -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Host "  Could not fetch aria2c: $_" -ForegroundColor DarkGray
    }
}

Write-Host "Downloading..." -ForegroundColor Cyan

if (Test-Path $Aria2Exe) {
    Write-Host "  Using aria2c (16 connections)..." -ForegroundColor DarkGray
    try {
        if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName               = $Aria2Exe
        $psi.Arguments              = "--split=16 --max-connection-per-server=16 --min-split-size=5M " +
                                      "--file-allocation=none --console-log-level=warn " +
                                      "--summary-interval=1 " +
                                      "--dir=`"$env:TEMP`" --out=winlibs.zip `"$Url`""
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError  = $true   # FIX 4: captured so we can surface errors
        $psi.UseShellExecute        = $false
        $psi.CreateNoWindow         = $true

        $proc       = [System.Diagnostics.Process]::Start($psi)
        $dlSw       = [System.Diagnostics.Stopwatch]::StartNew()
        $stderrLines = [System.Collections.Generic.List[string]]::new()

        # Read stderr asynchronously so it never blocks stdout reading
        $stderrJob = $proc.StandardError.ReadToEndAsync()

        while (-not $proc.HasExited) {
            $line = $proc.StandardOutput.ReadLine()
            if ($line -match '\[#\w+\s+([\d.]+\w+)/([\d.]+\w+)\((\d+)%\).*DL:([\d.]+\w+)') {
                $pct   = [int]$Matches[3]
                $done  = $Matches[1]
                $total = $Matches[2]
                $speed = $Matches[4]
                Show-ProgressBar -Status "Downloaded $done of $total | Speed: $speed/s" -Percent $pct
            }
        }
        $proc.WaitForExit()
        Clear-ProgressBar

        # FIX 4: surface any stderr output on failure
        $stderrText = $stderrJob.Result.Trim()
        if ($proc.ExitCode -eq 0 -and (Test-Path $ZipFile)) {
            $downloaded = $true
            Write-Host "  Download finished." -ForegroundColor Green
        } else {
            Write-Host "  aria2c exited with code $($proc.ExitCode), falling back..." -ForegroundColor DarkGray
            if ($stderrText) { Write-Host "  aria2c error: $stderrText" -ForegroundColor DarkGray }
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        }
    } catch {
        Clear-ProgressBar
        Write-Host "  aria2c failed: $_, falling back..." -ForegroundColor DarkGray
        if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
    } finally {
        # FIX 1: clean up aria2c exe after use
        Remove-Item $Aria2Exe -Force -ErrorAction SilentlyContinue
    }
} else {
    Write-Host "  aria2c unavailable, falling back..." -ForegroundColor DarkGray
}

# ================================================
# STRATEGY 2: Parallel chunk downloader — 8 streams
# ================================================
if (-not $downloaded) {
    Write-Host "  Using parallel chunk downloader (8 streams)..." -ForegroundColor DarkGray
    try {
        # Probe total size and follow redirects via HEAD
        $head = [System.Net.HttpWebRequest]::Create($Url)
        $head.Method            = 'HEAD'
        $head.UserAgent         = 'shams_gcc-installer/1.0'
        $head.AllowAutoRedirect = $true
        $headResp   = $head.GetResponse()
        $totalBytes = [int64]$headResp.ContentLength
        $finalUrl   = $headResp.ResponseUri.AbsoluteUri
        $headResp.Dispose()

        $numChunks  = 8
        $chunkSize  = [math]::Ceiling($totalBytes / $numChunks)
        $chunkFiles = @()
        $jobs       = @()

        for ($c = 0; $c -lt $numChunks; $c++) {
            $start     = [int64]($c * $chunkSize)
            $end       = [int64]([math]::Min($start + $chunkSize - 1, $totalBytes - 1))
            $chunkFile = "$env:TEMP\winlibs_chunk_$c.tmp"
            $chunkFiles += $chunkFile

            $jobs += Start-Job -ScriptBlock {
                param($u, $s, $e, $f)
                [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                $req = [System.Net.HttpWebRequest]::Create($u)
                $req.UserAgent         = 'shams_gcc-installer/1.0'
                $req.AllowAutoRedirect = $true
                $req.KeepAlive         = $true
                $req.AddRange($s, $e)
                $resp   = $req.GetResponse()
                $stream = $resp.GetResponseStream()
                $fs     = [System.IO.File]::Create($f)
                $buf    = New-Object byte[] (4MB)
                $read   = 0
                while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $fs.Write($buf, 0, $read) }
                $fs.Dispose(); $stream.Dispose(); $resp.Dispose()
            } -ArgumentList $finalUrl, $start, $end, $chunkFile
        }

        # Show progress while chunks download in parallel
        $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
        $uiSw = [System.Diagnostics.Stopwatch]::StartNew()
        while ($jobs | Where-Object { $_.State -eq 'Running' }) {
            if ($uiSw.ElapsedMilliseconds -ge 500) {
                $doneBytes = ($chunkFiles | ForEach-Object {
                    if (Test-Path $_) { (Get-Item $_).Length } else { 0 }
                } | Measure-Object -Sum).Sum
                $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                $speedMBps  = ($doneBytes / 1MB) / $elapsedSec
                $doneMB     = '{0:N2}' -f ($doneBytes / 1MB)
                $totalMB    = '{0:N2}' -f ($totalBytes / 1MB)
                $pct        = [math]::Min(100, [int](100L * $doneBytes / $totalBytes))
                Show-ProgressBar -Status "Downloaded $doneMB MB of $totalMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent $pct
                $uiSw.Restart()
            }
            Start-Sleep -Milliseconds 200
        }

        $failed = $jobs | Where-Object { $_.State -ne 'Completed' }
        $jobs | Remove-Job -Force
        if ($failed) { throw "One or more chunk downloads failed." }

        Clear-ProgressBar

        # Merge chunks into final ZIP
        Show-ProgressBar -Status "Merging chunks..." -Percent -1
        $outStream = [System.IO.File]::Create($ZipFile)
        try {
            foreach ($cf in $chunkFiles) {
                $inStream = [System.IO.File]::OpenRead($cf)
                $inStream.CopyTo($outStream)
                $inStream.Dispose()
            }
        } finally {
            $outStream.Dispose()
            $chunkFiles | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
        }
        Clear-ProgressBar

        $downloaded = $true
        Write-Host "  Download finished." -ForegroundColor Green

    } catch {
        Clear-ProgressBar
        Write-Host "  Parallel download failed: $_, using single-stream fallback..." -ForegroundColor DarkGray
        if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        if ($chunkFiles) { $chunkFiles | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue } }
    }
}

# ================================================
# STRATEGY 3: Single-stream fallback — 8 MB buffer
# ================================================
if (-not $downloaded) {
    Write-Host "  Using single-stream downloader..." -ForegroundColor DarkGray
    $request = [System.Net.HttpWebRequest]::Create($Url)
    $request.UserAgent         = 'shams_gcc-installer/1.0'
    $request.AllowAutoRedirect = $true
    $request.KeepAlive         = $true
    $request.Timeout           = 60000
    $request.ReadWriteTimeout  = 30000
    try {
        $response = $request.GetResponse()
        try {
            $totalBytes = [int64]$response.ContentLength
            $readStream = $response.GetResponseStream()
            $fileStream = [System.IO.File]::Create($ZipFile)
            try {
                $buffer    = New-Object byte[] (8MB)
                $totalRead = 0
                $read      = 0
                $dlSw      = [System.Diagnostics.Stopwatch]::StartNew()
                $uiSw      = [System.Diagnostics.Stopwatch]::StartNew()
                while (($read = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    $fileStream.Write($buffer, 0, $read)
                    $totalRead += $read
                    if ($uiSw.ElapsedMilliseconds -ge 500) {
                        $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                        $speedMBps  = ($totalRead / 1MB) / $elapsedSec
                        $doneMB     = '{0:N2}' -f ($totalRead / 1MB)
                        if ($totalBytes -gt 0) {
                            $pct     = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                            $totalMB = '{0:N2}' -f ($totalBytes / 1MB)
                            Show-ProgressBar -Status "Downloaded $doneMB MB of $totalMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent $pct
                        } else {
                            Show-ProgressBar -Status "Downloaded $doneMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent -1
                        }
                        $uiSw.Restart()
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
}

# ================================================
# Verify SHA-256 checksum
# ================================================
Write-Host "`nVerifying download..." -ForegroundColor Cyan
$actualHash = (Get-FileHash -Path $ZipFile -Algorithm SHA256).Hash
if ($actualHash -ne $ExpectedHash.ToUpper()) {
    Write-Host "  Checksum FAILED!" -ForegroundColor Red
    Write-Host "  Expected : $($ExpectedHash.ToUpper())" -ForegroundColor Red
    Write-Host "  Got      : $actualHash" -ForegroundColor Red
    Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
    Write-Host "  Corrupted file deleted." -ForegroundColor Yellow
    if ($attempt -lt $MaxRetries) { continue } else {
        Write-Host "  All $MaxRetries attempts failed. Please check your connection and try again." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  Checksum OK." -ForegroundColor Green

# Close retry loop — download succeeded
break

} # end retry loop

# ================================================
# Extract
# ================================================
Write-Host "`nExtracting..." -ForegroundColor Cyan

# Clean up any partial install dir before extracting
if (Test-Path $InstallDir) {
    Write-Host "  Removing previous/partial install..." -ForegroundColor DarkGray
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$extractOk = $false
try {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
    try {
        $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $n    = $fileEntries.Count
        $i    = 0
        $uiSw = [System.Diagnostics.Stopwatch]::StartNew()
        foreach ($entry in $fileEntries) {
            $i++
            $relative    = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath  = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($InstallDir, $relative))
            $installRoot = [System.IO.Path]::GetFullPath($InstallDir)
            if (-not $targetPath.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to extract outside install dir: $targetPath"
            }
            $destDir = [System.IO.Path]::GetDirectoryName($targetPath)
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)
            if ($uiSw.ElapsedMilliseconds -ge 250) {
                $pct = if ($n -gt 0) { [math]::Min(100, [int](100 * $i / $n)) } else { 100 }
                Show-ProgressBar -Status "Extracting file $i of $n ($pct%)" -Percent $pct
                $uiSw.Restart()
            }
        }
        $extractOk = $true
    } finally {
        $archive.Dispose()
        Clear-ProgressBar
    }
} catch {
    # Remove broken partial install on failure
    Write-Host "  Extraction failed: $_" -ForegroundColor Red
    Write-Host "  Cleaning up partial install..." -ForegroundColor Yellow
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  Extraction finished." -ForegroundColor Green
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# ================================================
# Add to PATH
# ================================================
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

# ================================================
# Show total elapsed time
# ================================================
$totalSw.Stop()
$elapsed = $totalSw.Elapsed
$elapsedStr = if ($elapsed.TotalMinutes -ge 1) {
    "$([int]$elapsed.TotalMinutes)m $($elapsed.Seconds)s"
} else {
    "$($elapsed.Seconds).$($elapsed.Milliseconds.ToString('D3').Substring(0,1))s"
}

Write-Host ""
Write-Host "Installation Completed! " -ForegroundColor Green -NoNewline
Write-Host "(finished in $elapsedStr)" -ForegroundColor DarkGray
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green
Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version"
Write-Host "   g++ --version`n"
