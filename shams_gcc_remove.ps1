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

    [switch]$DeleteFiles,

    [string[]]$ExtraPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Test-IsAdmin {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
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
        if ($n -eq (Normalize-PathText $d)) {
            return $true
        }
    }

    $patterns = @(
        "\\msys64\\",
        "\\mingw64\\",
        "\\mingw32\\",
        "\\ucrt64\\",
        "\\clang64\\",
        "\\winlibs\\",
        "\\tdm-gcc\\",
        "\\mingw\\",
        "\\gcc\\"
    )

    foreach ($p in $patterns) {
        if ($n -match [Regex]::Escape($p)) {
            return $true
        }
    }

    if ($n.EndsWith("\bin") -and ($n -match "mingw|winlibs|gcc|msys")) {
        return $true
    }

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

    $parts = Split-PathVariable $PathValue
    $forceList = @()
    if ($null -ne $ForceMatch) {
        $forceList = @($ForceMatch | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    }
    $keep = New-Object System.Collections.Generic.List[string]
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
    param([string[]]$BinDirs)

    $roots = New-Object System.Collections.Generic.HashSet[string]([StringComparer]::OrdinalIgnoreCase)

    foreach ($dir in $BinDirs) {
        $n = Normalize-PathText $dir
        if ([string]::IsNullOrWhiteSpace($n)) { continue }

        $parts = $n -split "\\"
        $markers = @("msys64", "winlibs", "tdm-gcc", "mingw64", "mingw32", "ucrt64", "clang64")

        foreach ($m in $markers) {
            $idx = [Array]::IndexOf($parts, $m)
            if ($idx -ge 0) {
                if ($m -in @("mingw64", "mingw32", "ucrt64", "clang64") -and $idx -gt 0) {
                    [void]$roots.Add(($parts[0..($idx - 1)] -join "\"))
                } else {
                    [void]$roots.Add(($parts[0..$idx] -join "\"))
                }
                break
            }
        }

        if ($n.EndsWith("\bin")) {
            [void]$roots.Add($n.Substring(0, $n.Length - 4))
        }
    }

    return @($roots)
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

    $HWND_BROADCAST = [IntPtr]0xffff
    $WM_SETTINGCHANGE = 0x1A
    $SMTO_ABORTIFHUNG = 0x2
    $result = [IntPtr]::Zero
    [void][EnvBroadcast]::SendMessageTimeout(
        $HWND_BROADCAST,
        $WM_SETTINGCHANGE,
        [IntPtr]::Zero,
        "Environment",
        $SMTO_ABORTIFHUNG,
        5000,
        [ref]$result
    )
}

function Confirm-YesNo {
    param(
        [string]$PromptText,
        [switch]$DefaultNo
    )

    while ($true) {
        $suffix = if ($DefaultNo) { "[y/N]" } else { "[Y/n]" }
        $reply = Read-Host "$PromptText $suffix"
        if ([string]::IsNullOrWhiteSpace($reply)) {
            return (-not $DefaultNo)
        }
        switch ($reply.Trim().ToLowerInvariant()) {
            "y" { return $true }
            "yes" { return $true }
            "n" { return $false }
            "no" { return $false }
            default { Write-Host "Please type y or n." -ForegroundColor Yellow }
        }
    }
}

if (($Scope -eq "Machine" -or $Scope -eq "All") -and -not (Test-IsAdmin)) {
    Write-Warning "Machine PATH edits require Administrator PowerShell."
    if ($Scope -eq "Machine") {
        Write-Error "Run as Administrator or use -Scope User."
        exit 1
    }
}

$gccBinDirs = @(Get-GccBinDirs)
Write-Host ""
Write-Host "Detected gcc/g++ bin directories:" -ForegroundColor Cyan
if (@($gccBinDirs).Count -eq 0) {
    Write-Host "  (none found from current PATH)" -ForegroundColor Yellow
} else {
    $gccBinDirs | ForEach-Object { Write-Host "  - $_" }
}

$targets = @()
if ($Scope -in @("User", "All")) { $targets += "User" }
if ($Scope -in @("Machine", "All")) { $targets += "Machine" }

$changedAny = $false
$planByTarget = @{}

foreach ($target in $targets) {
    $current = [Environment]::GetEnvironmentVariable("Path", $target)
    $result = Remove-MatchingPathEntries -PathValue $current -KnownBinDirs $gccBinDirs -ForceMatch $ExtraPath
    $planByTarget[$target] = $result

    Write-Host ""
    Write-Host "[$target PATH]" -ForegroundColor Cyan
    Write-Host ("  Entries total     : {0}" -f @($result.OriginalParts).Count)
    Write-Host ("  Entries to remove : {0}" -f @($result.RemovedParts).Count)
    foreach ($r in $result.RemovedParts) {
        Write-Host "    - $r"
    }

    if (@($result.RemovedParts).Count -gt 0) {
        $changedAny = $true
        Write-Host "  Action: ready to update (pending confirmation)" -ForegroundColor Yellow
    } else {
        Write-Host "  Action: no changes needed"
    }
}

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
    foreach ($target in $targets) {
        $result = $planByTarget[$target]
        if (@($result.RemovedParts).Count -eq 0) { continue }
        try {
            Set-PathByScope -TargetScope $target -Value $result.NewValue
            Write-Host "[$target PATH] updated." -ForegroundColor Green
        } catch {
            Write-Warning "[$target PATH] failed to update ($($_.Exception.Message))"
        }
    }
    Send-EnvironmentChanged
    Write-Host ""
    Write-Host "Environment change broadcast sent." -ForegroundColor Green
} elseif ($changedAny) {
    Write-Host ""
    Write-Host "PATH removal skipped by user." -ForegroundColor Yellow
}

if ($DeleteFiles) {
    Write-Host ""
    Write-Host "[TOOLCHAIN FOLDER REMOVAL]" -ForegroundColor Cyan
    $roots = Get-ToolchainRoots -BinDirs $gccBinDirs

    if (@($roots).Count -eq 0) {
        Write-Host "  No candidate folders detected."
    } else {
        Write-Host "  Candidate folders:"
        $roots | ForEach-Object { Write-Host "    - $_" }

        $shouldDelete = $Force
        if (-not $Force) {
            Write-Host ""
            $shouldDelete = Confirm-YesNo -PromptText "Delete these toolchain folders from disk?" -DefaultNo
        }

        if ($shouldDelete) {
            foreach ($root in $roots) {
                if (-not (Test-Path -LiteralPath $root)) {
                    Write-Host "  not found    $root"
                    continue
                }
                try {
                    Remove-Item -LiteralPath $root -Recurse -Force -ErrorAction Stop
                    Write-Host "  deleted      $root" -ForegroundColor Green
                } catch {
                    Write-Warning "  failed       $root ($($_.Exception.Message))"
                }
            }
        } else {
            Write-Host "  Folder deletion skipped by user." -ForegroundColor Yellow
        }
    }
}

Write-Host ""
if ($changedAny) {
    Write-Host "Done." -ForegroundColor Green
} else {
    Write-Host "Nothing to remove." -ForegroundColor Yellow
}
