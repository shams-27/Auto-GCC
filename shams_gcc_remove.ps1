# ================================================
# remove_gcc.ps1 - GCC/G++ remover for Windows
# ================================================
# Supports common installs:
# - MSYS2 / MinGW (ucrt64, mingw64, mingw32, clang64)
# - WinLibs
# ================================================

[CmdletBinding()]
param(
    [ValidateSet("User", "Machine", "All")]
    [string]$Scope = "All",

    [switch]$Force,

    [string[]]$ExtraPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
$ProgressPreference    = 'SilentlyContinue'

# ------------------------------------------------
# Progress bar helpers (Windows-safe, no ANSI)
# ------------------------------------------------
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
        [Console]::WriteLine("")
        [Console]::WriteLine("")
        $script:_pbRow = $Host.UI.RawUI.CursorPosition.Y - 2
    }

    [Console]::SetCursorPosition(0, $script:_pbRow)
    $padded = $Status.PadRight($winWidth - 1).Substring(0, $winWidth - 1)
    [Console]::ForegroundColor = [ConsoleColor]::Cyan
    [Console]::Write($padded)

    [Console]::SetCursorPosition(0, $script:_pbRow + 1)
    [Console]::Write('[' + ('0' * $filled) + (' ' * $empty) + ']')
    [Console]::ResetColor()
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
# ASCII Art
# ------------------------------------------------
Write-Host ""
$lines = @(
    ' _______  _______  _______    _______  _______  _______  _______           _______  _______ ',
    '(  ____ \(  ____ \(  ____ \  (  ____ )(  ____ \(       )(  ___  )|\     /|(  ____ \(  ____ )',
    '| (    \/| (    \/| (    \/  | (    )|| (    \/| () () || (   ) || )   ( || (    \/| (    )|',
    '| |      | |      | |        | (____)|| (__    | || || || |   | || |   | || (__    | (____)|',
    '| | ____ | |      | |        |     __)|  __)   | |(_)| || |   | |( (   ) )|  __)   |     __)',
    '| | \_  )| |      | |        | (\ (   | (      | |   | || |   | | \ \_/ / | (      | (\ (   ',
    '| (___) || (____/\| (____/\  | ) \ \__| (____/\| )   ( || (___) |  \   /  | (____/\| ) \ \__',
    '(_______)(_______/(_______/  |/   \__/(_______/|/     \|(_______)   \_/   (_______/|/   \__/'
)

$split = 28

foreach ($line in $lines) {
    [Console]::ForegroundColor = [ConsoleColor]::Blue
    [Console]::Write($line.Substring(0, $split))
    [Console]::ForegroundColor = [ConsoleColor]::DarkRed
    [Console]::WriteLine($line.Substring($split))
}

[Console]::ResetColor()
Write-Host ""

# ------------------------------------------------
# Helper functions
# ------------------------------------------------
function Test-IsAdmin {
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Normalize-PathText {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) { return "" }
    $expanded = [Environment]::ExpandEnvironmentVariables($PathText.Trim().Trim('"'))
    $expanded = $expanded.TrimEnd('\', '/')
    try {
        return [IO.Path]::GetFullPath($expanded).ToLowerInvariant()
    } catch {
        return $expanded.ToLowerInvariant()
    }
}

function Get-CommandPaths {
    param([string]$CommandName)
    try {
        $items = Get-Command $CommandName -All -ErrorAction Stop |
            Where-Object { $_.CommandType -in @("Application", "ExternalScript") } |
            Select-Object -ExpandProperty Source -Unique
        return @($items)
    } catch {
        return @()
    }
}

function Get-GccBinDirs {
    $all = @()
    $all += Get-CommandPaths -CommandName "gcc.exe"
    $all += Get-CommandPaths -CommandName "g++.exe"
    $all += Get-CommandPaths -CommandName "gcc"
    $all += Get-CommandPaths -CommandName "g++"

    $dirs = $all |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
        ForEach-Object { Split-Path -Path $_ -Parent } |
        Select-Object -Unique

    return @($dirs)
}

function Test-LooksLikeGccPath {
    param(
        [string]$PathEntry,
        [string[]]$KnownBinDirs
    )

    $n = Normalize-PathText $PathEntry
    if ([string]::IsNullOrWhiteSpace($n)) { return $false }

    foreach ($d in $KnownBinDirs) {
        if ($n -eq (Normalize-PathText $d)) { return $true }
    }

    $patterns = @(
        "\\msys64\\", "\\mingw64\\", "\\mingw32\\", "\\ucrt64\\",
        "\\clang64\\", "\\winlibs\\", "\\tdm-gcc\\", "\\mingw\\", "\\gcc\\"
    )

    foreach ($p in $patterns) {
        if ($n -match [Regex]::Escape($p)) { return $true }
    }

    if ($n.EndsWith("\bin") -and ($n -match "mingw|winlibs|gcc|msys")) { return $true }

    return $false
}

function Split-PathVariable {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return @($PathValue -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Remove-MatchingPathEntries {
    param(
        [string]$PathValue,
        [string[]]$KnownBinDirs,
        [string[]]$ForceMatch
    )

    $parts     = Split-PathVariable $PathValue
    $forceList = @()
    if ($null -ne $ForceMatch) {
        $forceList = @($ForceMatch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $keep    = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]

    foreach ($part in $parts) {
        $remove = Test-LooksLikeGccPath -PathEntry $part -KnownBinDirs $KnownBinDirs

        if (-not $remove -and $forceList.Length -gt 0) {
            $np = Normalize-PathText $part
            foreach ($f in $forceList) {
                $nf = Normalize-PathText $f
                if (-not [string]::IsNullOrWhiteSpace($nf) -and ($np.Contains($nf) -or $nf.Contains($np))) {
                    $remove = $true
                    break
                }
            }
        }

        if ($remove) { $removed.Add($part) } else { $keep.Add($part) }
    }

    return [PSCustomObject]@{
        OriginalParts = $parts
        KeptParts     = @($keep)
        RemovedParts  = @($removed)
        NewValue      = ($keep -join ";")
    }
}

function Get-ToolchainRoots {
    param(
        [string[]]$BinDirs,
        [string[]]$AdditionalPathEntries
    )

    $roots   = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)
    $sources = @()
    if ($null -ne $BinDirs)                { $sources += @($BinDirs) }
    if ($null -ne $AdditionalPathEntries)  { $sources += @($AdditionalPathEntries) }

    foreach ($dir in $sources) {
        $n = Normalize-PathText $dir
        if ([string]::IsNullOrWhiteSpace($n)) { continue }

        $parts   = $n -split "\\"
        $markers = @("msys64", "winlibs", "tdm-gcc", "mingw64", "mingw32", "ucrt64", "clang64")

        foreach ($m in $markers) {
            $idx = [Array]::LastIndexOf($parts, $m)
            if ($idx -ge 0) {
                [void]$roots.Add(($parts[0..$idx] -join "\"))
                break
            }
        }

        if ($n.EndsWith("\bin")) {
            [void]$roots.Add($n.Substring(0, $n.Length - 4))
        }
    }

    $fallbackRoots = @(
        "C:\msys64", "C:\mingw64", "C:\mingw32", "C:\mingw",
        "C:\winlibs", "C:\tdm-gcc",
        "$env:ProgramFiles\winlibs",
        "$env:ProgramFiles\mingw-w64",
        "$env:ProgramFiles(x86)\mingw-w64"
    )
    foreach ($candidate in $fallbackRoots) {
        if (-not [string]::IsNullOrWhiteSpace($candidate) -and (Test-Path -LiteralPath $candidate)) {
            [void]$roots.Add((Normalize-PathText $candidate))
        }
    }

    return @($roots | Where-Object { $_ -and $_ -match "^[a-zA-Z]:\\" -and $_ -ne "c:\" })
}

function Set-PathByScope {
    param(
        [ValidateSet("User", "Machine")]
        [string]$TargetScope,
        [string]$Value
    )
    [Environment]::SetEnvironmentVariable("Path", $Value, $TargetScope)
}

function Send-EnvironmentChanged {
    $signature = @"
using System;
using System.Runtime.InteropServices;
public static class EnvBroadcast {
    [DllImport("user32.dll", SetLastError=true, CharSet=CharSet.Unicode)]
    public static extern IntPtr SendMessageTimeout(
        IntPtr hWnd, int Msg, IntPtr wParam, string lParam,
        int fuFlags, int uTimeout, out IntPtr lpdwResult);
}
"@
    if (-not ("EnvBroadcast" -as [type])) {
        Add-Type -TypeDefinition $signature | Out-Null
    }
    $HWND_BROADCAST  = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x2
    $result = [IntPtr]::Zero
    [void][EnvBroadcast]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]::Zero,
        "Environment", $SMTO_ABORTIFHUNG, 5000, [ref]$result
    )
}

function Confirm-YesNo {
    param(
        [string]$PromptText,
        [switch]$DefaultNo
    )
    while ($true) {
        $suffix = if ($DefaultNo) { "[y/N]" } else { "[Y/n]" }
        $reply  = Read-Host "$PromptText $suffix"
        if ([string]::IsNullOrWhiteSpace($reply)) { return (-not $DefaultNo) }
        switch ($reply.Trim().ToLowerInvariant()) {
            "y"   { return $true }
            "yes" { return $true }
            "n"   { return $false }
            "no"  { return $false }
            default {
                [Console]::ForegroundColor = [ConsoleColor]::Yellow
                [Console]::WriteLine("Please type y or n.")
                [Console]::ResetColor()
            }
        }
    }
}

# ------------------------------------------------
# Main
# ------------------------------------------------
if (($Scope -eq "Machine" -or $Scope -eq "All") -and -not (Test-IsAdmin)) {
    Write-Warning "Machine PATH edits require Administrator PowerShell."
    if ($Scope -eq "Machine") {
        Write-Error "Run as Administrator or use -Scope User."
        exit 1
    }
}

$gccBinDirs = @(Get-GccBinDirs)
Write-Host ""
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("Detected gcc/g++ bin directories:")
[Console]::ResetColor()
if (@($gccBinDirs).Count -eq 0) {
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("  (none found from current PATH)")
    [Console]::ResetColor()
} else {
    $gccBinDirs | ForEach-Object { [Console]::WriteLine("  - $_") }
}

$targets      = @()
if ($Scope -in @("User",    "All")) { $targets += "User" }
if ($Scope -in @("Machine", "All")) { $targets += "Machine" }

$changedAny   = $false
$deletedAny   = $false
$planByTarget = @{}

foreach ($target in $targets) {
    $current = [Environment]::GetEnvironmentVariable("Path", $target)
    $result  = Remove-MatchingPathEntries -PathValue $current -KnownBinDirs $gccBinDirs -ForceMatch $ExtraPath
    $planByTarget[$target] = $result

    Write-Host ""
    [Console]::ForegroundColor = [ConsoleColor]::Cyan
    [Console]::WriteLine("[$target PATH]")
    [Console]::ResetColor()
    [Console]::WriteLine("  Entries total     : {0}" -f @($result.OriginalParts).Count)
    [Console]::WriteLine("  Entries to remove : {0}" -f @($result.RemovedParts).Count)
    foreach ($r in $result.RemovedParts) { [Console]::WriteLine("    - $r") }

    if (@($result.RemovedParts).Count -gt 0) {
        $changedAny = $true
        [Console]::ForegroundColor = [ConsoleColor]::Yellow
        [Console]::WriteLine("  Action: ready to update (pending confirmation)")
        [Console]::ResetColor()
    } else {
        [Console]::WriteLine("  Action: no changes needed")
    }
}

$removedEntriesAll = @(
    $planByTarget.Values |
        ForEach-Object { @($_.RemovedParts) } |
        Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

$shouldApplyPath = $false
if ($changedAny) {
    if ($Force) {
        $shouldApplyPath = $true
    } else {
        Write-Host ""
        $shouldApplyPath = Confirm-YesNo -PromptText "Remove detected GCC-related PATH entries now?" -DefaultNo
    }
}

if ($shouldApplyPath) {
    $pathTargetsToUpdate = @($targets | Where-Object { @($planByTarget[$_].RemovedParts).Count -gt 0 })
    $pathTotal = @($pathTargetsToUpdate).Count
    $pathIndex = 0

    Write-Host ""
    foreach ($target in $targets) {
        $result = $planByTarget[$target]
        if (@($result.RemovedParts).Count -eq 0) { continue }
        $pathIndex++
        $pct = if ($pathTotal -gt 0) { [int](100 * $pathIndex / $pathTotal) } else { 100 }
        Show-ProgressBar -Status ("Updating {0} PATH ({1}/{2})" -f $target, $pathIndex, $pathTotal) -Percent $pct
        try {
            Set-PathByScope -TargetScope $target -Value $result.NewValue
        } catch {
            Clear-ProgressBar
            Write-Warning "[$target PATH] failed to update ($($_.Exception.Message))"
        }
    }
    Clear-ProgressBar

    Send-EnvironmentChanged
    [Console]::ForegroundColor = [ConsoleColor]::Green
    [Console]::WriteLine("PATH updated successfully.")
    [Console]::WriteLine("Environment change broadcast sent.")
    [Console]::ResetColor()
} elseif ($changedAny) {
    Write-Host ""
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("PATH removal skipped by user.")
    [Console]::ResetColor()
}

Write-Host ""
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("[TOOLCHAIN FOLDER REMOVAL]")
[Console]::ResetColor()
$roots = Get-ToolchainRoots -BinDirs $gccBinDirs -AdditionalPathEntries $removedEntriesAll

if (@($roots).Count -eq 0) {
    [Console]::WriteLine("  No candidate folders detected.")
} else {
    [Console]::WriteLine("  Candidate folders:")
    $roots | ForEach-Object { [Console]::WriteLine("    - $_") }

    $shouldDelete = $Force
    if (-not $Force) {
        Write-Host ""
        $shouldDelete = Confirm-YesNo -PromptText "Delete these toolchain folders from disk?" -DefaultNo
    }

    if ($shouldDelete) {
        $deleteTotal = @($roots).Count
        $deleteIndex = 0
        Write-Host ""
        foreach ($root in $roots) {
            $deleteIndex++
            $pct = if ($deleteTotal -gt 0) { [int](100 * $deleteIndex / $deleteTotal) } else { 100 }
            Show-ProgressBar -Status ("Deleting folder {0}/{1}: {2}" -f $deleteIndex, $deleteTotal, $root) -Percent $pct
            if (-not (Test-Path -LiteralPath $root)) {
                Clear-ProgressBar
                [Console]::WriteLine("  not found    $root")
                continue
            }
            try {
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
                Clear-ProgressBar
                [Console]::ForegroundColor = [ConsoleColor]::Green
                [Console]::WriteLine("  deleted      $root")
                [Console]::ResetColor()
                $deletedAny = $true
            } catch {
                Clear-ProgressBar
                Write-Warning "  failed       $root ($($_.Exception.Message))"
            }
        }
        if ($script:_pbRow -ge 0) { Clear-ProgressBar }
    } else {
        [Console]::ForegroundColor = [ConsoleColor]::Yellow
        [Console]::WriteLine("  Folder deletion skipped by user.")
        [Console]::ResetColor()
    }
}

Write-Host ""
if ($changedAny -or $deletedAny) {
    [Console]::ForegroundColor = [ConsoleColor]::Green
    [Console]::WriteLine("Done.")
} else {
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("Nothing to remove.")
}
[Console]::ResetColor()
