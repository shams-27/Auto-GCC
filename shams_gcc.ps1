# ===================================================
# shams_gcc.ps1 - Automated GCC Installer for Windows
# ===================================================
# Purpose:
#   Downloads, verifies, extracts, and installs a GCC/G++ toolchain
#   (WinLibs MinGW-w64 build) and registers it in the user's PATH.
#
# Toolchain installed:
#   WinLibs GCC 16.1.0 (x86_64, POSIX threads, SEH exceptions, UCRT runtime)
#   Source: https://github.com/brechtsanders/winlibs_mingw
#
# Download strategy (tried in order until one succeeds):
#   1. aria2c      — 16 parallel connections (fastest)
#   2. Chunk downloader — 8 parallel HTTP range-request jobs (fallback)
#   3. Single-stream — standard HttpWebRequest with 8 MB buffer (last resort)
#
# Requirements:
#   - Windows 10/11 x64
#   - Internet access
#   - The script auto-elevates to Administrator if not already elevated
# ===================================================

Clear-Host

# ================================================
# Auto-Elevate to Administrator
# ================================================
# GCC is installed to C:\mingw64 and the PATH is updated at Machine or User scope,
# both of which may require elevated rights. If this session is not already running
# as Administrator, relaunch the same script with RunAs elevation and exit.
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {

    # Prefer PowerShell 7+ (pwsh) if available; fall back to Windows PowerShell
    $shellExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }

    # Relaunch this script file with Administrator privileges
    Start-Process $shellExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return   # Exit the non-elevated instance
}

# ================================================
# Progress Bar Helpers  
# ================================================
# Tracks the console row where the progress bar is anchored.
# -1 means no progress bar is currently displayed.
$script:_pbRow = -1

# Draws or refreshes a two-line winget-style progress bar:
#
#   Line 1 (status):  status text in cyan, right-aligned percentage in white
#   Line 2 (bar):     [████████████░░░░░░░░░░░░]
#
# Fill character  : U+2588 FULL BLOCK  (█)
# Empty character : U+2591 LIGHT SHADE (░)
#
# If $Percent is negative the bar pulses in indeterminate mode (fully filled,
# shown in DarkCyan instead of Cyan to distinguish it visually).
#
# On the first call, two blank lines are reserved and the row is recorded.
function Show-ProgressBar {
    param(
        [string]$Status,   # Descriptive text shown above the bar
        [int]   $Percent   # 0–100 completion level; negative = indeterminate
    )

    $winWidth  = $Host.UI.RawUI.WindowSize.Width

    # ── Line 1: status + percentage ──────────────────────────────────────────
    $pctLabel = if ($Percent -lt 0) { '  --  ' } else { "$Percent%" }
    # Right-align the percentage: reserve enough space at the end for "100%"
    $pctPad   = 5   # max width of "100%" + one leading space
    $statusWidth = [Math]::Max(1, $winWidth - 1 - $pctPad)
    # Truncate/pad the status text to fit its allocated width
    $statusStr = if ($Status.Length -gt $statusWidth) {
        $Status.Substring(0, $statusWidth)
    } else {
        $Status.PadRight($statusWidth)
    }
    $pctStr = $pctLabel.PadLeft($pctPad)

    # ── Line 2: bar graphic ───────────────────────────────────────────────────
    # Reserve 2 chars for '|' and '|', 1 char margin → inner width
    $barInner = [Math]::Max(10, $winWidth - 3)
    $indeterminate = $Percent -lt 0
    $filled = if ($indeterminate) {
        $barInner
    } else {
        [Math]::Min($barInner, [int](($barInner * $Percent) / 100))
    }
    $empty  = $barInner - $filled
    $bar    = '|' + ([char]0x2588 -as [string]) * $filled + ([char]0x2591 -as [string]) * $empty + '|'

    # ── Reserve two lines on first call ──────────────────────────────────────
    if ($script:_pbRow -lt 0) {
        $script:_pbRow = $Host.UI.RawUI.CursorPosition.Y
        [Console]::WriteLine()
        [Console]::WriteLine()
    }

    # ── Render line 1 ────────────────────────────────────────────────────────
    [Console]::SetCursorPosition(0, $script:_pbRow)
    $Host.UI.RawUI.ForegroundColor = if ($indeterminate) { [ConsoleColor]::DarkCyan } else { [ConsoleColor]::Cyan }
    [Console]::Write($statusStr)
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::White
    [Console]::Write($pctStr)

    # ── Render line 2 ────────────────────────────────────────────────────────
    [Console]::SetCursorPosition(0, $script:_pbRow + 1)
    $Host.UI.RawUI.ForegroundColor = if ($indeterminate) { [ConsoleColor]::DarkBlue } else { [ConsoleColor]::Blue }
    [Console]::Write($bar)

    # ── Reset color ──────────────────────────────────────────────────────────
    $Host.UI.RawUI.ForegroundColor = [ConsoleColor]::White
}

# Erases both progress bar lines by overwriting them with spaces,
# resets the cursor to the bar's start row, and marks the bar as inactive.
function Clear-ProgressBar {
    if ($script:_pbRow -lt 0) { return }  # Nothing to clear

    $winWidth = $Host.UI.RawUI.WindowSize.Width
    $blank    = ' ' * ($winWidth - 1)

    [Console]::SetCursorPosition(0, $script:_pbRow)
    [Console]::WriteLine($blank)
    [Console]::WriteLine($blank)
    [Console]::SetCursorPosition(0, $script:_pbRow)

    $script:_pbRow = -1  # Mark bar as not active
}

# ================================================
# ASCII Art Banner
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

# Character column where the color switches from Blue to DarkYellow
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
# Pre-install Check: GCC Already Present?
# ================================================
# If gcc is already on the PATH there is nothing to install.
# Report the location and exit early to avoid overwriting a working installation.
$existingGcc = Get-Command gcc -ErrorAction SilentlyContinue
if ($existingGcc) {
    $gccDir = Split-Path -Path $existingGcc.Path
    Write-Host "GCC is already available on this system." -ForegroundColor Green
    Write-Host "Found directory: $gccDir"                -ForegroundColor Cyan
    Write-Host "Skipping installation process.`n"        -ForegroundColor Yellow
    return
}

# ================================================
# Configuration
# ================================================
# Installation target directory on disk
$InstallDir = "C:\mingw64"

# The bin directory that will be appended to the user PATH
$BinPath = "$InstallDir\mingw64\bin"

# Direct download URL for the WinLibs GCC ZIP (x86_64, posix, seh, ucrt)
$Url = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"

# Expected SHA-256 hash of the official ZIP — used to detect corruption or tampering
$ExpectedHash = "325771F545E89F62C0E1FAFDBF0066CC49E3321AECA7B704C8D065E97A72F2FB"

# Number of download retry attempts before giving up
$MaxRetries = 3

# Temporary file paths used during download
$ZipFile = "$env:TEMP\winlibs.zip"     # Final downloaded ZIP
$Aria2Exe = "$env:TEMP\aria2c.exe"       # Extracted aria2c binary (Strategy 1)
$Aria2Zip = "$env:TEMP\aria2.zip"        # aria2c release ZIP

# URL to fetch aria2c (used only if it isn't already cached in TEMP)
$Aria2Url = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"

# Ensure TLS 1.2 is used for all .NET HTTP requests (required by GitHub)
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# Start a stopwatch to measure total installation time
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

# ================================================
# Download + Verify Loop  (retries up to $MaxRetries times)
# ================================================
# The loop tries each of the three download strategies in order.
# On checksum failure the corrupted file is deleted and the loop retries.
# On success the loop breaks out immediately.
for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

    if ($attempt -gt 1) {
        Write-Host "`nRetrying... (attempt $attempt of $MaxRetries)" -ForegroundColor Yellow
    }

    # Flag: set to $true as soon as any strategy successfully writes the ZIP
    $downloaded = $false

    # --------------------------------------------
    # STRATEGY 1: aria2c — 16 Parallel Connections
    # --------------------------------------------
    # aria2c is the fastest option as it splits the download into 16 concurrent
    # TCP connections. We fetch the aria2c binary itself first if not cached.
    Write-Host "Preparing download..." -ForegroundColor Cyan

    # Download and extract aria2c only if it isn't already in TEMP
    if (-not (Test-Path $Aria2Exe)) {
        Write-Host "  Fetching aria2c..." -ForegroundColor DarkGray
        try {
            # Download the aria2c release ZIP using WebClient (small file, synchronous is fine)
            $wc = New-Object System.Net.WebClient
            $wc.DownloadFile($Aria2Url, $Aria2Zip)
            $wc.Dispose()

            # Extract only aria2c.exe from the release ZIP
            Add-Type -AssemblyName System.IO.Compression.FileSystem
            $az = [System.IO.Compression.ZipFile]::OpenRead($Aria2Zip)
            try {
                $exeEntry = $az.Entries | Where-Object { $_.Name -eq 'aria2c.exe' } | Select-Object -First 1
                if ($exeEntry) {
                    [System.IO.Compression.ZipFileExtensions]::ExtractToFile($exeEntry, $Aria2Exe, $true)
                }
            }
            finally { $az.Dispose() }

            # Clean up the aria2 release ZIP now that we have the executable
            Remove-Item $Aria2Zip -Force -ErrorAction SilentlyContinue
        }
        catch {
            Write-Host "  Could not fetch aria2c: $_" -ForegroundColor DarkGray
            # Non-fatal: fall through to Strategy 2/3
        }
    }

    Write-Host "Downloading..." -ForegroundColor Cyan

    if (Test-Path $Aria2Exe) {
        Write-Host "  Using aria2c (16 connections)..." -ForegroundColor DarkGray
        try {
            # Remove any previous partial download before starting
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

            # Build the aria2c process: 16 splits, 16 connections per server, 5 MB min-split
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $Aria2Exe
            $psi.Arguments = "--split=16 --max-connection-per-server=16 --min-split-size=5M " +
            "--file-allocation=none --console-log-level=warn " +
            "--summary-interval=1 " +
            "--dir=`"$env:TEMP`" --out=winlibs.zip `"$Url`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true   # Capture errors for diagnostics
            $psi.UseShellExecute = $false
            $psi.CreateNoWindow = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
            $stderrLines = [System.Collections.Generic.List[string]]::new()

            # Read stderr asynchronously to prevent stdout-reading from blocking
            $stderrJob = $proc.StandardError.ReadToEndAsync()

            # Parse aria2c's stdout progress lines and update the progress bar
            while (-not $proc.HasExited) {
                $line = $proc.StandardOutput.ReadLine()
                # aria2c progress line format: [#xxxxxxxx SIZE/TOTAL(PCT%) DL:SPEED]
                if ($line -match '\[#\w+\s+([\d.]+\w+)/([\d.]+\w+)\((\d+)%\).*DL:([\d.]+\w+)') {
                    $pct = [int]$Matches[3]   # Completion percentage
                    $done = $Matches[1]         # Downloaded amount (with unit)
                    $total = $Matches[2]         # Total size (with unit)
                    $speed = $Matches[4]         # Current download speed
                    Show-ProgressBar -Status "Downloaded $done of $total | Speed: $speed/s" -Percent $pct
                }
            }
            $proc.WaitForExit()
            Clear-ProgressBar

            # Surface any stderr output if the download failed
            $stderrText = $stderrJob.Result.Trim()
            if ($proc.ExitCode -eq 0 -and (Test-Path $ZipFile)) {
                $downloaded = $true
                Write-Host "  Download finished." -ForegroundColor Green
            }
            else {
                Write-Host "  aria2c exited with code $($proc.ExitCode), falling back..." -ForegroundColor DarkGray
                if ($stderrText) { Write-Host "  aria2c error: $stderrText" -ForegroundColor DarkGray }
                if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
            }
        }
        catch {
            Clear-ProgressBar
            Write-Host "  aria2c failed: $_, falling back..." -ForegroundColor DarkGray
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        }
        finally {
            # Always clean up the aria2c binary after this attempt
            Remove-Item $Aria2Exe -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Write-Host "  aria2c unavailable, falling back..." -ForegroundColor DarkGray
    }

    # --------------------------------------------
    # STRATEGY 2: Parallel Chunk Downloader — 8 Streams
    # --------------------------------------------
    # Uses HTTP Range requests to split the file into 8 equal chunks,
    # each downloaded in a separate PowerShell background job simultaneously.
    # Chunks are merged into a single ZIP once all jobs complete.
    if (-not $downloaded) {
        Write-Host "  Using parallel chunk downloader (8 streams)..." -ForegroundColor DarkGray
        try {
            # Issue a HEAD request to get the total file size and resolve any redirects
            $head = [System.Net.HttpWebRequest]::Create($Url)
            $head.Method = 'HEAD'
            $head.UserAgent = 'shams_gcc-installer/1.0'
            $head.AllowAutoRedirect = $true
            $headResp = $head.GetResponse()
            $totalBytes = [int64]$headResp.ContentLength   # Total ZIP size in bytes
            $finalUrl = $headResp.ResponseUri.AbsoluteUri # URL after redirect resolution
            $headResp.Dispose()

            $numChunks = 8
            $chunkSize = [math]::Ceiling($totalBytes / $numChunks)
            $chunkFiles = @()   # Temp file paths for each chunk
            $jobs = @()   # Background job handles

            # Launch one background job per chunk using HTTP Range: bytes=start-end
            for ($c = 0; $c -lt $numChunks; $c++) {
                $start = [int64]($c * $chunkSize)
                $end = [int64]([math]::Min($start + $chunkSize - 1, $totalBytes - 1))
                $chunkFile = "$env:TEMP\winlibs_chunk_$c.tmp"
                $chunkFiles += $chunkFile

                # Each job downloads its byte range and writes it to a temp file
                $jobs += Start-Job -ScriptBlock {
                    param($u, $s, $e, $f)
                    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
                    $req = [System.Net.HttpWebRequest]::Create($u)
                    $req.UserAgent = 'shams_gcc-installer/1.0'
                    $req.AllowAutoRedirect = $true
                    $req.KeepAlive = $true
                    $req.AddRange($s, $e)   # Request only this chunk's byte range
                    $resp = $req.GetResponse()
                    $stream = $resp.GetResponseStream()
                    $fs = [System.IO.File]::Create($f)
                    $buf = New-Object byte[] (4MB)
                    $read = 0
                    while (($read = $stream.Read($buf, 0, $buf.Length)) -gt 0) { $fs.Write($buf, 0, $read) }
                    $fs.Dispose(); $stream.Dispose(); $resp.Dispose()
                } -ArgumentList $finalUrl, $start, $end, $chunkFile
            }

            # Poll chunk file sizes every 500 ms to show aggregate download progress
            $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
            $uiSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($jobs | Where-Object { $_.State -eq 'Running' }) {
                if ($uiSw.ElapsedMilliseconds -ge 500) {
                    # Sum the current size of all chunk temp files
                    $doneBytes = ($chunkFiles | ForEach-Object {
                            if (Test-Path $_) { (Get-Item $_).Length } else { 0 }
                        } | Measure-Object -Sum).Sum

                    $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                    $speedMBps = ($doneBytes / 1MB) / $elapsedSec
                    $doneMB = '{0:N2}' -f ($doneBytes / 1MB)
                    $totalMB = '{0:N2}' -f ($totalBytes / 1MB)
                    $pct = [math]::Min(100, [int](100L * $doneBytes / $totalBytes))
                    Show-ProgressBar -Status "Downloaded $doneMB MB of $totalMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent $pct
                    $uiSw.Restart()
                }
                Start-Sleep -Milliseconds 200
            }

            # Check that all jobs completed successfully
            $failed = $jobs | Where-Object { $_.State -ne 'Completed' }
            $jobs | Remove-Job -Force
            if ($failed) { throw "One or more chunk downloads failed." }

            Clear-ProgressBar

            # Merge all chunk temp files into the final ZIP in order
            Show-ProgressBar -Status "Merging chunks..." -Percent -1
            $outStream = [System.IO.File]::Create($ZipFile)
            try {
                foreach ($cf in $chunkFiles) {
                    $inStream = [System.IO.File]::OpenRead($cf)
                    $inStream.CopyTo($outStream)
                    $inStream.Dispose()
                }
            }
            finally {
                $outStream.Dispose()
                # Clean up all chunk temp files regardless of merge success
                $chunkFiles | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue }
            }
            Clear-ProgressBar

            $downloaded = $true
            Write-Host "  Download finished." -ForegroundColor Green
        }
        catch {
            Clear-ProgressBar
            Write-Host "  Parallel download failed: $_, using single-stream fallback..." -ForegroundColor DarkGray
            # Clean up any partial output files before falling through
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
            if ($chunkFiles) { $chunkFiles | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue } }
        }
    }

    # --------------------------------------------
    # STRATEGY 3: Single-Stream Fallback — 8 MB Buffer
    # --------------------------------------------
    # Standard single-connection HttpWebRequest read loop.
    # Updates the progress bar every 500 ms. If ContentLength is unavailable
    # (e.g. chunked transfer), the bar runs in indeterminate mode.
    if (-not $downloaded) {
        Write-Host "  Using single-stream downloader..." -ForegroundColor DarkGray

        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.UserAgent = 'shams_gcc-installer/1.0'
        $request.AllowAutoRedirect = $true
        $request.KeepAlive = $true
        $request.Timeout = 60000   # 60 s connect timeout
        $request.ReadWriteTimeout = 30000   # 30 s per-read timeout

        try {
            $response = $request.GetResponse()
            try {
                $totalBytes = [int64]$response.ContentLength   # -1 if unknown
                $readStream = $response.GetResponseStream()
                $fileStream = [System.IO.File]::Create($ZipFile)
                try {
                    $buffer = New-Object byte[] (8MB)   # 8 MB read buffer
                    $totalRead = 0
                    $read = 0
                    $dlSw = [System.Diagnostics.Stopwatch]::StartNew()   # Speed calculation
                    $uiSw = [System.Diagnostics.Stopwatch]::StartNew()   # UI refresh throttle

                    while (($read = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                        $fileStream.Write($buffer, 0, $read)
                        $totalRead += $read

                        # Refresh the progress bar at most every 500 ms to avoid console flicker
                        if ($uiSw.ElapsedMilliseconds -ge 500) {
                            $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                            $speedMBps = ($totalRead / 1MB) / $elapsedSec
                            $doneMB = '{0:N2}' -f ($totalRead / 1MB)

                            if ($totalBytes -gt 0) {
                                # Known total size: show determinate percentage
                                $pct = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                                $totalMB = '{0:N2}' -f ($totalBytes / 1MB)
                                Show-ProgressBar -Status "Downloaded $doneMB MB of $totalMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent $pct
                            }
                            else {
                                # Unknown total size: show indeterminate bar
                                Show-ProgressBar -Status "Downloaded $doneMB MB | Speed: $($speedMBps.ToString('N2')) MB/s" -Percent -1
                            }
                            $uiSw.Restart()
                        }
                    }
                }
                finally {
                    # Always flush and close both streams
                    $fileStream.Dispose()
                    $readStream.Dispose()
                }
            }
            finally {
                $response.Dispose()
            }
        }
        finally {
            Clear-ProgressBar
        }
        Write-Host "  Download finished." -ForegroundColor Green
    }

    # --------------------------------------------
    # SHA-256 Checksum Verification
    # --------------------------------------------
    # Compare the downloaded file's hash against the known-good hash.
    # A mismatch means the file is corrupted or was tampered with; delete
    # it and retry (up to $MaxRetries times).
    Write-Host "`nVerifying download..." -ForegroundColor Cyan
    $actualHash = (Get-FileHash -Path $ZipFile -Algorithm SHA256).Hash

    if ($actualHash -ne $ExpectedHash.ToUpper()) {
        Write-Host "  Checksum FAILED!"                     -ForegroundColor Red
        Write-Host "  Expected : $($ExpectedHash.ToUpper())" -ForegroundColor Red
        Write-Host "  Got      : $actualHash"               -ForegroundColor Red
        Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
        Write-Host "  Corrupted file deleted."              -ForegroundColor Yellow

        if ($attempt -lt $MaxRetries) {
            continue   # Retry the download
        }
        else {
            Write-Host "  All $MaxRetries attempts failed. Please check your connection and try again." -ForegroundColor Red
            exit 1
        }
    }
    Write-Host "  Checksum OK." -ForegroundColor Green

    # Download and verification succeeded — exit the retry loop
    break

} # end retry loop

# ================================================
# Extract the ZIP to the Install Directory
# ================================================
Write-Host "`nExtracting..." -ForegroundColor Cyan

# Remove any previous or partial installation to ensure a clean state
if (Test-Path $InstallDir) {
    Write-Host "  Removing previous/partial install..." -ForegroundColor DarkGray
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$extractOk = $false

try {
    $archive = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
    try {
        # Get only file entries (skip directory entries whose names end with '/')
        $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
        $n = $fileEntries.Count
        $i = 0
        $uiSw = [System.Diagnostics.Stopwatch]::StartNew()

        foreach ($entry in $fileEntries) {
            $i++

            # Convert forward-slash ZIP paths to Windows backslash paths
            $relative = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($InstallDir, $relative))
            $installRoot = [System.IO.Path]::GetFullPath($InstallDir)

            # Security check: refuse to extract any entry that would escape the install dir
            # (defends against "zip slip" path-traversal attacks)
            if (-not $targetPath.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Refusing to extract outside install dir: $targetPath"
            }

            # Create the destination directory if it doesn't exist yet
            $destDir = [System.IO.Path]::GetDirectoryName($targetPath)
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            # Extract this entry, overwriting if a file already exists
            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)

            # Throttle progress bar updates to every 250 ms to reduce console overhead
            if ($uiSw.ElapsedMilliseconds -ge 250) {
                $pct = if ($n -gt 0) { [math]::Min(100, [int](100 * $i / $n)) } else { 100 }
                Show-ProgressBar -Status "Extracting file $i of $n ($pct%)" -Percent $pct
                $uiSw.Restart()
            }
        }
        $extractOk = $true
    }
    finally {
        # Always close the archive and clear the progress bar
        $archive.Dispose()
        Clear-ProgressBar
    }
}
catch {
    # On any extraction error, remove the partial install and the ZIP, then abort
    Write-Host "  Extraction failed: $_"            -ForegroundColor Red
    Write-Host "  Cleaning up partial install..."   -ForegroundColor Yellow
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
    exit 1
}

Write-Host "  Extraction finished." -ForegroundColor Green

# Remove the downloaded ZIP now that extraction is complete
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# ================================================
# Register GCC bin Directory in the User PATH
# ================================================
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")

# Only update PATH if the bin directory isn't already present
if ($CurrentPath -notlike "*$BinPath*") {
    Write-Host ""

    # Animate the PATH update with a short progress bar for visual feedback.
    # The actual registry write happens at the midpoint of the animation steps.
    $pathSteps = 22
    $applyAt = [math]::Ceiling($pathSteps / 2)   # Step at which to write to registry
    $applied = $false

    for ($s = 1; $s -le $pathSteps; $s++) {
        # Write the new PATH value at the midpoint of the animation
        if (-not $applied -and $s -ge $applyAt) {
            [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
            $applied = $true
        }
        $pct = [math]::Min(100, [int](100 * $s / $pathSteps))
        Show-ProgressBar -Status "Updating user PATH ($pct%)" -Percent $pct
        Start-Sleep -Milliseconds 38   # ~38 ms per step ≈ ~840 ms total animation
    }

    # Safety: apply the PATH change if the midpoint was somehow never reached
    if (-not $applied) {
        [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    }

    Clear-ProgressBar
    Write-Host "PATH Updated" -ForegroundColor Green
}

# ================================================
# Show Total Elapsed Time and Final Instructions
# ================================================
$totalSw.Stop()
$elapsed = $totalSw.Elapsed

# Format elapsed time: "Xm Ys" for durations over a minute, "X.Ys" for under
$elapsedStr = if ($elapsed.TotalMinutes -ge 1) {
    "$([int]$elapsed.TotalMinutes)m $($elapsed.Seconds)s"
}
else {
    # Show one decimal place of seconds (e.g. "4.7s")
    "$($elapsed.Seconds).$($elapsed.Milliseconds.ToString('D3').Substring(0,1))s"
}

Write-Host ""
Write-Host "Installation Completed! " -ForegroundColor Green -NoNewline
Write-Host "(finished in $elapsedStr)"  -ForegroundColor DarkGray
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green
Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version"
Write-Host "   g++ --version`n"
