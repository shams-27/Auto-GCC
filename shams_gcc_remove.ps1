# ================================================
# remove_gcc.ps1 - GCC/G++ Remover for Windows
# ================================================
# Purpose:
#   Detects and removes GCC/G++ toolchain entries from the Windows
#   PATH environment variable, and optionally deletes the toolchain
#   folders from disk.
#
# Supported toolchain installations:
#   - MSYS2 / MinGW  (ucrt64, mingw64, mingw32, clang64)
#   - WinLibs
#   - TDM-GCC
#
# Parameters:
#   -Scope     : Which PATH to clean — "User", "Machine", or "All" (default: All)
#   -Force     : Skip all confirmation prompts and apply changes automatically
#   -ExtraPath : Additional path strings to force-match and remove (optional)
#
# Requirements:
#   - Administrator rights are required when Scope is "Machine" or "All"
# ================================================

[CmdletBinding()]
param(
    # Determines whether to clean the User PATH, Machine PATH, or both
    [ValidateSet("User", "Machine", "All")]
    [string]$Scope = "All",

    # When set, skips all yes/no confirmation prompts and applies all changes
    [switch]$Force,

    # Optional extra path substrings to forcibly remove (in addition to auto-detected ones)
    [string[]]$ExtraPath
)

Clear-Host

# Enforce strict variable scoping to catch typos and undefined variables
Set-StrictMode -Version Latest

# Stop immediately on any error instead of silently continuing
$ErrorActionPreference = "Stop"

# Hide the built-in PowerShell progress bar (it slows down some operations)
$ProgressPreference = 'SilentlyContinue'

# ------------------------------------------------
# Progress Bar Helpers
# ------------------------------------------------
# Tracks the console row where the progress bar is rendered.
# -1 means no progress bar is currently displayed.
$script:_pbRow = -1

# Draws or updates a two-line progress bar in the console.
# Line 1: status text (padded/clipped to window width)
# Line 2: filled bar using '0' chars and spaces
# If $Percent is negative, the bar renders as fully filled (indeterminate).
function Show-ProgressBar {
    param(
        [string]$Status,   # Text to display above the bar
        [int]   $Percent   # 0–100 completion; negative = full/indeterminate
    )

    $winWidth = $Host.UI.RawUI.WindowSize.Width
    # Inner bar width: subtract 2 for the surrounding '[' and ']'
    $barInner = [Math]::Max(10, $winWidth - 3)

    # Calculate how many characters to fill vs leave empty
    $filled = if ($Percent -lt 0) {
        $barInner   # Indeterminate: fill the entire bar
    }
    else {
        [Math]::Min($barInner, [int](($barInner * $Percent) / 100))
    }
    $empty = $barInner - $filled

    # On first call, reserve two blank lines and record their starting row
    if ($script:_pbRow -lt 0) {
        [Console]::WriteLine("")
        [Console]::WriteLine("")
        $script:_pbRow = $Host.UI.RawUI.CursorPosition.Y - 2
    }

    # Overwrite line 1 with the status text (cyan)
    [Console]::SetCursorPosition(0, $script:_pbRow)
    $padded = $Status.PadRight($winWidth - 1).Substring(0, $winWidth - 1)
    [Console]::ForegroundColor = [ConsoleColor]::Cyan
    [Console]::Write($padded)

    # Overwrite line 2 with the bar graphic
    [Console]::SetCursorPosition(0, $script:_pbRow + 1)
    [Console]::Write('[' + ('0' * $filled) + (' ' * $empty) + ']')
    [Console]::ResetColor()
}

# Erases the progress bar by blanking both reserved lines,
# then resets the row tracker so future calls start fresh.
function Clear-ProgressBar {
    if ($script:_pbRow -lt 0) { return }  # Nothing to clear

    $winWidth = $Host.UI.RawUI.WindowSize.Width
    $blank = ' ' * ($winWidth - 1)

    # Blank out both lines
    [Console]::SetCursorPosition(0, $script:_pbRow)
    [Console]::WriteLine($blank)
    [Console]::WriteLine($blank)
    [Console]::SetCursorPosition(0, $script:_pbRow)

    # Mark bar as not active
    $script:_pbRow = -1
}

# ------------------------------------------------
# ASCII Art Banner
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

# Split point between the two color sections ("GCC REMOVER" branding)
$split = 28

# Print each banner line: first part in Blue, remainder in DarkRed
foreach ($line in $lines) {
    [Console]::ForegroundColor = [ConsoleColor]::Blue
    [Console]::Write($line.Substring(0, $split))
    [Console]::ForegroundColor = [ConsoleColor]::DarkRed
    [Console]::WriteLine($line.Substring($split))
}

[Console]::ResetColor()
Write-Host ""

# ------------------------------------------------
# Helper Functions
# ------------------------------------------------

# Returns $true if the current PowerShell process is running as Administrator.
# Required for editing the Machine-level PATH registry key.
function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# Normalizes a path string for reliable comparison:
#   - Expands environment variables (e.g. %USERPROFILE%)
#   - Strips surrounding quotes and trailing slashes
#   - Resolves to an absolute path (via GetFullPath)
#   - Converts to lowercase so comparisons are case-insensitive
# Returns an empty string if the input is null/whitespace.
function Normalize-PathText {
    param([string]$PathText)
    if ([string]::IsNullOrWhiteSpace($PathText)) { return "" }

    $expanded = [Environment]::ExpandEnvironmentVariables($PathText.Trim().Trim('"'))
    $expanded = $expanded.TrimEnd('\', '/')

    try {
        return [IO.Path]::GetFullPath($expanded).ToLowerInvariant()
    }
    catch {
        # GetFullPath can fail on malformed paths; fall back to simple lowercasing
        return $expanded.ToLowerInvariant()
    }
}

# Finds all filesystem paths for a given command name using Get-Command.
# Filters to only executable types (Application or ExternalScript).
# Returns an array of unique source paths, or an empty array if not found.
function Get-CommandPaths {
    param([string]$CommandName)
    try {
        $items = Get-Command $CommandName -All -ErrorAction Stop |
        Where-Object { $_.CommandType -in @("Application", "ExternalScript") } |
        Select-Object -ExpandProperty Source -Unique
        return @($items)
    }
    catch {
        return @()
    }
}

# Discovers the bin directories that currently contain gcc/g++ executables
# by querying Get-Command for both .exe and extension-less variants.
# Returns an array of unique parent directory paths.
function Get-GccBinDirs {
    $all = @()
    $all += Get-CommandPaths -CommandName "gcc.exe"
    $all += Get-CommandPaths -CommandName "g++.exe"
    $all += Get-CommandPaths -CommandName "gcc"
    $all += Get-CommandPaths -CommandName "g++"

    # Extract the parent folder of each found executable, deduplicate
    $dirs = $all |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) } |
    ForEach-Object { Split-Path -Path $_ -Parent } |
    Select-Object -Unique

    return @($dirs)
}

# Determines whether a single PATH entry looks like it belongs to a GCC toolchain.
# Two strategies:
#   1. Exact match against $KnownBinDirs (directories where gcc/g++ were found)
#   2. Pattern match against well-known toolchain directory name fragments
# Returns $true if either check passes.
function Test-LooksLikeGccPath {
    param(
        [string]$PathEntry,      # A single semicolon-separated PATH entry
        [string[]]$KnownBinDirs  # Directories confirmed to contain gcc/g++
    )

    $n = Normalize-PathText $PathEntry
    if ([string]::IsNullOrWhiteSpace($n)) { return $false }

    # Strategy 1: exact match against confirmed gcc bin dirs
    foreach ($d in $KnownBinDirs) {
        if ($n -eq (Normalize-PathText $d)) { return $true }
    }

    # Strategy 2: substring/pattern match for known toolchain folder names
    $patterns = @(
        "\\msys64\\", "\\mingw64\\", "\\mingw32\\", "\\ucrt64\\",
        "\\clang64\\", "\\winlibs\\", "\\tdm-gcc\\", "\\mingw\\", "\\gcc\\"
    )

    foreach ($p in $patterns) {
        if ($n -match [Regex]::Escape($p)) { return $true }
    }

    # Extra heuristic: any \bin directory whose parent name contains toolchain keywords
    if ($n.EndsWith("\bin") -and ($n -match "mingw|winlibs|gcc|msys")) { return $true }

    return $false
}

# Splits a semicolon-delimited PATH string into an array of individual entries,
# discarding any empty or whitespace-only segments.
# Returns an empty array if the input is null/whitespace.
function Split-PathVariable {
    param([string]$PathValue)
    if ([string]::IsNullOrWhiteSpace($PathValue)) { return @() }
    return @($PathValue -split ";" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

# Scans all entries in a PATH string and separates them into two lists:
#   - RemovedParts : entries identified as GCC-related (to be removed)
#   - KeptParts    : all other entries (to be retained)
#
# Also accepts a $ForceMatch list of path substrings; any entry whose normalized
# path contains (or is contained by) a force-match string will also be removed.
#
# Returns a PSCustomObject with:
#   OriginalParts  - original array of all entries
#   KeptParts      - entries that will be retained
#   RemovedParts   - entries that will be removed
#   NewValue       - the resulting PATH string (KeptParts joined by ";")
function Remove-MatchingPathEntries {
    param(
        [string]$PathValue,      # Raw PATH string (semicolon-separated)
        [string[]]$KnownBinDirs, # Confirmed gcc/g++ bin directories
        [string[]]$ForceMatch    # Optional extra substrings to force-remove
    )

    $parts = Split-PathVariable $PathValue

    # Normalize the force-match list, ignoring blank entries
    $forceList = @()
    if ($null -ne $ForceMatch) {
        $forceList = @($ForceMatch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }

    $keep = New-Object System.Collections.Generic.List[string]
    $removed = New-Object System.Collections.Generic.List[string]

    foreach ($part in $parts) {
        # Primary check: does this entry look like a GCC path?
        $remove = Test-LooksLikeGccPath -PathEntry $part -KnownBinDirs $KnownBinDirs

        # Secondary check: does it match any force-match substring?
        if (-not $remove -and $forceList.Length -gt 0) {
            $np = Normalize-PathText $part
            foreach ($f in $forceList) {
                $nf = Normalize-PathText $f
                # Match if either string contains the other (handles partial path matching)
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
        NewValue      = ($keep -join ";")   # Reconstructed PATH without removed entries
    }
}

# Attempts to identify the root installation directories of GCC toolchains
# so they can optionally be deleted from disk entirely.
#
# Two discovery strategies:
#   1. Walk each bin directory upward until a known toolchain marker folder name
#      is found (e.g. "msys64", "mingw64") — that marker folder is the root.
#   2. If the path ends in \bin, treat the parent as the root.
#
# Also checks a hardcoded list of common default install locations as a fallback.
#
# Filters out results that are drive roots (e.g. "C:\") to prevent accidental
# mass deletion.
function Get-ToolchainRoots {
    param(
        [string[]]$BinDirs,              # Confirmed gcc/g++ bin directories
        [string[]]$AdditionalPathEntries # Extra removed PATH entries to scan
    )

    # Use a HashSet for automatic deduplication (case-insensitive)
    $roots = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)

    # Combine both input lists into one source to process
    $sources = @()
    if ($null -ne $BinDirs) { $sources += @($BinDirs) }
    if ($null -ne $AdditionalPathEntries) { $sources += @($AdditionalPathEntries) }

    foreach ($dir in $sources) {
        $n = Normalize-PathText $dir
        if ([string]::IsNullOrWhiteSpace($n)) { continue }

        # Split the normalized path into individual folder name segments
        $parts = $n -split "\\"
        $markers = @("msys64", "winlibs", "tdm-gcc", "mingw64", "mingw32", "ucrt64", "clang64")

        # Walk through the path parts looking for a known toolchain folder marker
        foreach ($m in $markers) {
            $idx = [Array]::LastIndexOf($parts, $m)
            if ($idx -ge 0) {
                # Reconstruct the path up to and including the marker segment
                [void]$roots.Add(($parts[0..$idx] -join "\"))
                break
            }
        }

        # If the path ends in \bin, treat the parent directory as the root
        if ($n.EndsWith("\bin")) {
            [void]$roots.Add($n.Substring(0, $n.Length - 4))
        }
    }

    # Fallback: also probe well-known default install locations
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

    # Filter out anything that isn't a valid absolute Windows path or is a drive root
    return @($roots | Where-Object { $_ -and $_ -match "^[a-zA-Z]:\\" -and $_ -ne "c:\" })
}

# Persists a new PATH value to either User or Machine scope in the registry
# via the .NET Environment API.
function Set-PathByScope {
    param(
        [ValidateSet("User", "Machine")]
        [string]$TargetScope,  # Which registry hive to write to
        [string]$Value         # The new PATH string
    )
    [Environment]::SetEnvironmentVariable("Path", $Value, $TargetScope)
}

# Broadcasts a WM_SETTINGCHANGE message to all top-level windows so that
# running applications (e.g. File Explorer) pick up the updated PATH
# without requiring a reboot.
# Uses P/Invoke to call the Win32 SendMessageTimeout API.
function Send-EnvironmentChanged {
    # Define the C# P/Invoke signature for SendMessageTimeout (only once per session)
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
    # Add the type only if it hasn't been compiled in this session yet
    if (-not ("EnvBroadcast" -as [type])) {
        Add-Type -TypeDefinition $signature | Out-Null
    }

    $HWND_BROADCAST = [IntPtr]0xffff  # Broadcast to all top-level windows
    $WM_SETTINGCHANGE = 0x1A          # Windows message: settings have changed
    $SMTO_ABORTIFHUNG = 0x2           # Skip hung windows instead of waiting forever
    $result = [IntPtr]::Zero

    [void][EnvBroadcast]::SendMessageTimeout(
        $HWND_BROADCAST, $WM_SETTINGCHANGE, [IntPtr]::Zero,
        "Environment",       # lParam: tells recipients which setting changed
        $SMTO_ABORTIFHUNG,
        5000,                # Timeout: 5 seconds per window
        [ref]$result
    )
}

# Prompts the user for a yes/no answer and keeps looping until a valid reply is given.
# Pressing Enter without input returns the default ($true unless -DefaultNo is set).
# Returns $true for yes, $false for no.
function Confirm-YesNo {
    param(
        [string]$PromptText,  # The question to display
        [switch]$DefaultNo    # If set, Enter defaults to No; otherwise defaults to Yes
    )
    while ($true) {
        $suffix = if ($DefaultNo) { "[y/N]" } else { "[Y/n]" }
        $reply = Read-Host "$PromptText $suffix"

        # Empty input: use the default
        if ([string]::IsNullOrWhiteSpace($reply)) { return (-not $DefaultNo) }

        switch ($reply.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default {
                # Invalid input: prompt again
                [Console]::ForegroundColor = [ConsoleColor]::Yellow
                [Console]::WriteLine("Please type y or n.")
                [Console]::ResetColor()
            }
        }
    }
}

# ------------------------------------------------
# Main Script Logic
# ------------------------------------------------

# Guard: editing the Machine PATH requires elevated (Administrator) privileges.
# If running without elevation, warn and exit when Machine scope is required.
if (($Scope -eq "Machine" -or $Scope -eq "All") -and -not (Test-IsAdmin)) {
    Write-Warning "Machine PATH edits require Administrator PowerShell."
    if ($Scope -eq "Machine") {
        Write-Error "Run as Administrator or use -Scope User."
        exit 1
    }
    # If Scope is "All" and not admin, the script continues but will only modify User PATH
}

# --- Step 1: Detect currently active gcc/g++ bin directories ---
$gccBinDirs = @(Get-GccBinDirs)

Write-Host ""
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("Detected gcc/g++ bin directories:")
[Console]::ResetColor()

if (@($gccBinDirs).Count -eq 0) {
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("  (none found from current PATH)")
    [Console]::ResetColor()
}
else {
    $gccBinDirs | ForEach-Object { [Console]::WriteLine("  - $_") }
}

# --- Step 2: Build the list of PATH scopes to process based on -Scope parameter ---
$targets = @()
if ($Scope -in @("User", "All")) { $targets += "User" }
if ($Scope -in @("Machine", "All")) { $targets += "Machine" }

# Flags to track whether anything was actually changed or deleted
$changedAny = $false
$deletedAny = $false

# Dictionary to store per-scope removal plans (keyed by "User" / "Machine")
$planByTarget = @{}

# --- Step 3: Analyse each PATH scope and build a removal plan ---
foreach ($target in $targets) {
    # Read the raw PATH value from the registry for this scope
    $current = [Environment]::GetEnvironmentVariable("Path", $target)

    # Identify which entries to remove
    $result = Remove-MatchingPathEntries -PathValue $current -KnownBinDirs $gccBinDirs -ForceMatch $ExtraPath
    $planByTarget[$target] = $result

    # Display a summary of what will change for this scope
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
    }
    else {
        [Console]::WriteLine("  Action: no changes needed")
    }
}

# Collect all removed path entries across scopes (used later for toolchain root detection)
$removedEntriesAll = @(
    $planByTarget.Values |
    ForEach-Object { @($_.RemovedParts) } |
    Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
)

# --- Step 4: Confirm and apply PATH changes ---
$shouldApplyPath = $false
if ($changedAny) {
    if ($Force) {
        # -Force flag bypasses the prompt
        $shouldApplyPath = $true
    }
    else {
        Write-Host ""
        $shouldApplyPath = Confirm-YesNo -PromptText "Remove detected GCC-related PATH entries now?" -DefaultNo
    }
}

if ($shouldApplyPath) {
    # Only process scopes that actually have entries to remove
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
        }
        catch {
            Clear-ProgressBar
            Write-Warning "[$target PATH] failed to update ($($_.Exception.Message))"
        }
    }
    Clear-ProgressBar

    # Notify running processes that the environment has changed
    Send-EnvironmentChanged

    [Console]::ForegroundColor = [ConsoleColor]::Green
    [Console]::WriteLine("PATH updated successfully.")
    [Console]::WriteLine("Environment change broadcast sent.")
    [Console]::ResetColor()
}
elseif ($changedAny) {
    # Changes were pending but the user declined
    Write-Host ""
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("PATH removal skipped by user.")
    [Console]::ResetColor()
}

# --- Step 5: Detect and optionally delete toolchain folders from disk ---
Write-Host ""
[Console]::ForegroundColor = [ConsoleColor]::Cyan
[Console]::WriteLine("[TOOLCHAIN FOLDER REMOVAL]")
[Console]::ResetColor()

# Discover candidate toolchain root directories to potentially delete
$roots = Get-ToolchainRoots -BinDirs $gccBinDirs -AdditionalPathEntries $removedEntriesAll

if (@($roots).Count -eq 0) {
    [Console]::WriteLine("  No candidate folders detected.")
}
else {
    [Console]::WriteLine("  Candidate folders:")
    $roots | ForEach-Object { [Console]::WriteLine("    - $_") }

    # Ask user (or use -Force) whether to delete the folders
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

            # Skip folders that no longer exist (may have been removed already)
            if (-not (Test-Path -LiteralPath $root)) {
                Clear-ProgressBar
                [Console]::WriteLine("  not found    $root")
                continue
            }

            try {
                # Recursively delete the toolchain folder
                Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
                Clear-ProgressBar
                [Console]::ForegroundColor = [ConsoleColor]::Green
                [Console]::WriteLine("  deleted      $root")
                [Console]::ResetColor()
                $deletedAny = $true
            }
            catch {
                Clear-ProgressBar
                Write-Warning "  failed       $root ($($_.Exception.Message))"
            }
        }

        # Clean up progress bar if it is still visible after the loop
        if ($script:_pbRow -ge 0) { Clear-ProgressBar }
    }
    else {
        [Console]::ForegroundColor = [ConsoleColor]::Yellow
        [Console]::WriteLine("  Folder deletion skipped by user.")
        [Console]::ResetColor()
    }
}

# --- Step 6: Final status summary ---
Write-Host ""
if ($changedAny -or $deletedAny) {
    [Console]::ForegroundColor = [ConsoleColor]::Green
    [Console]::WriteLine("Done.")
}
else {
    [Console]::ForegroundColor = [ConsoleColor]::Yellow
    [Console]::WriteLine("Nothing to remove.")
}
[Console]::ResetColor()
