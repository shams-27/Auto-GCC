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
    $shellExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Start-Process $shellExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$tempScript`""
    exit
}

Write-Host ""
$asciiArt = @"
 _______          _________ _______    _______  _______  _______ 
(  ___  )|\     /|\__   __/(  ___  )  (  ____ \(  ____ \(  ____ \
| (   ) || )   ( |   ) (   | (   ) |  | (    \/| (    \/| (    \/
| (___) || |   | |   | |   | |   | |  | |      | |      | |      
|  ___  || |   | |   | |   | |   | |  | | ____ | |      | |      
| (   ) || |   | |   | |   | |   | |  | | \_  )| |      | |      
| )   ( || (___) |   | |   | (___) |  | (___) || (____/\| (____/\
|/     \|(_______)   )_(   (_______)  (_______)(_______/(_______/
"@

Write-Host $asciiArt -ForegroundColor Cyan
Write-Host ""

# Use PowerShell 7+ minimal progress rendering when available.
# Falls back automatically on Windows PowerShell 5.1.
if ($PSVersionTable.PSVersion.Major -ge 7 -and $null -ne $PSStyle -and $null -ne $PSStyle.Progress) {
    $PSStyle.Progress.View = 'Minimal'
}

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
            $buffer = New-Object byte[] (1MB)
            $totalRead = 0
            $read = 0
            $downloadStopwatch = [System.Diagnostics.Stopwatch]::StartNew()
            while (($read = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                $elapsedSeconds = [math]::Max(0.001, $downloadStopwatch.Elapsed.TotalSeconds)
                $speedMBps = ($totalRead / 1MB) / $elapsedSeconds
                if ($totalBytes -gt 0) {
                    $pct = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                    Write-Progress -Id 1 -Activity 'Downloading Mingw-w64' `
                        -Status ("{0}% | {1:N1} MB/s" -f $pct, $speedMBps) `
                        -PercentComplete $pct
                } else {
                    Write-Progress -Id 1 -Activity 'Downloading Mingw-w64' `
                        -Status ('{0:N1} MB | {1:N1} MB/s' -f ($totalRead / 1MB), $speedMBps) `
                        -PercentComplete -1
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
    Write-Progress -Id 1 -Activity 'Downloading Mingw-w64' -Completed
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
        Write-Progress -Id 2 -Activity 'Extracting Mingw-w64' `
            -Status ("{0}%" -f $pct) `
            -PercentComplete $pct
    }
} finally {
    $archive.Dispose()
    Write-Progress -Id 2 -Activity 'Extracting Mingw-w64' -Completed
}

Write-Host "  Extraction finished." -ForegroundColor Green

if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# Add to PATH
$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    Write-Host ""
    $pathSteps = 22
    $applyAt = [math]::Ceiling($pathSteps / 2)
    $applied = $false
    for ($s = 1; $s -le $pathSteps; $s++) {
        if (-not $applied -and $s -ge $applyAt) {
            [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
            $applied = $true
        }
        $pct = [math]::Min(100, [int](100 * $s / $pathSteps))
        Write-Progress -Id 3 -Activity 'Updating user PATH' `
            -Status ("{0}%" -f $pct) `
            -PercentComplete $pct
        Start-Sleep -Milliseconds 38
    }
    if (-not $applied) {
        [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    }
    Write-Progress -Id 3 -Activity 'Updating user PATH' -Completed
    Write-Host "PATH Updated" -ForegroundColor Green
}

Write-Host "Installation Completed!" -ForegroundColor Green
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green
Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version"
Write-Host "   g++ --version`n"

$shamsColors = @('DarkRed', 'DarkYellow', 'DarkGreen', 'DarkCyan', 'DarkMagenta')
$shamsLetters = 'SHAMS'.ToCharArray()

Write-Host "`nMade by " -ForegroundColor Cyan -NoNewline
for ($i = 0; $i -lt $shamsLetters.Length; $i++) {
    $isLast = ($i -eq $shamsLetters.Length - 1)
    Write-Host $shamsLetters[$i] -ForegroundColor $shamsColors[$i] -NoNewline:(-not $isLast)
}
Write-Host "`n"
