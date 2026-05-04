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

Write-Host "`nAuto GCC Installer" -ForegroundColor Cyan
Write-Host "====================================`n" -ForegroundColor Cyan

$InstallDir = "C:\mingw64"
$BinPath    = "$InstallDir\mingw64\bin"
$Url        = "https://github.com/brechtsanders/winlibs_mingw/releases/download/16.1.0posix-14.0.0-ucrt-r1/winlibs-x86_64-posix-seh-gcc-16.1.0-mingw-w64ucrt-14.0.0-r1.zip"
$ZipFile    = "$env:TEMP\winlibs.zip"

Write-Host "Downloading GCC/G++..." -ForegroundColor Cyan

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
            while (($read = $readStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $fileStream.Write($buffer, 0, $read)
                $totalRead += $read
                if ($totalBytes -gt 0) {
                    $pct = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                    Write-Progress -Activity 'Downloading GCC/G++' `
                        -Status ('{0:N1} MB of {1:N1} MB' -f ($totalRead / 1MB), ($totalBytes / 1MB)) `
                        -PercentComplete $pct
                } else {
                    Write-Progress -Activity 'Downloading GCC/G++' `
                        -Status ('{0:N1} MB downloaded (size unknown)' -f ($totalRead / 1MB)) `
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
    Write-Progress -Activity 'Downloading GCC/G++' -Completed
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
        Write-Progress -Activity 'Extracting GCC/G++' `
            -CurrentOperation $entry.FullName `
            -Status ("File {0} of {1}" -f $i, $n) `
            -PercentComplete $pct
    }
} finally {
    $archive.Dispose()
    Write-Progress -Activity 'Extracting GCC/G++' -Completed
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
        $status = if ($s -lt $applyAt) { 'Preparing user PATH...' } else { 'Writing PATH change...' }
        Write-Progress -Activity 'Updating user PATH' `
            -Status $status `
            -CurrentOperation $BinPath `
            -PercentComplete $pct
        Start-Sleep -Milliseconds 38
    }
    if (-not $applied) {
        [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    }
    Write-Progress -Activity 'Updating user PATH' -Completed
    Write-Host "PATH Updated" -ForegroundColor Green
}

Write-Host "Installation Completed!" -ForegroundColor Green
Write-Host "GCC is at: $BinPath\gcc.exe" -ForegroundColor Green
Write-Host "`nRestart PowerShell and test:" -ForegroundColor Yellow
Write-Host "   gcc --version"
Write-Host "   g++ --version`n"
Write-Host "`nMade by Shams`n" -ForegroundColor Cyan
