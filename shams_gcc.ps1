# =============================================================================
# shams_gcc.ps1  —  Automated GCC Toolchain Installer for Windows
# =============================================================================
#
# OVERVIEW
#   Downloads, verifies, extracts, and configures a GCC/G++ toolchain
#   (WinLibs MinGW-w64 build), then registers the binary directory in the
#   current user's PATH environment variable.
#
# TOOLCHAIN
#   WinLibs MinGW-w64  |  x86_64  |  POSIX threads  |  SEH  |  UCRT
#   Version : resolved at runtime from the GitHub Releases API (always latest)
#   Source  : https://github.com/brechtsanders/winlibs_mingw
#
# DOWNLOAD STRATEGIES  (attempted in priority order)
#   1. aria2c           — 16 parallel connections for maximum throughput
#   2. Chunk downloader — 8 parallel HTTP range-request workers (fallback)
#   3. Single-stream    — HttpWebRequest with an 8 MB buffer (last resort)
#
# REQUIREMENTS
#   - Windows 10 / 11 (x86_64)
#   - PowerShell 5.1 or later
#   - Active internet connection
#   - Administrator privileges (the script self-elevates when needed)
# =============================================================================

Set-StrictMode -Off
$ErrorActionPreference = 'Stop'

# =============================================================================
# Privilege Escalation
# =============================================================================
# Detects whether the current session holds Administrator rights. If not, the
# script relaunches itself in an elevated process using the most capable
# PowerShell host available (pwsh preferred over powershell).
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator)) {
    $shellExe = if (Get-Command pwsh -ErrorAction SilentlyContinue) { "pwsh" } else { "powershell" }
    Start-Process $shellExe -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`""
    return
}

Clear-Host
[Console]::CursorVisible = $false

# Force UTF-8 output so that Unicode box-drawing characters and Braille spinner
# glyphs render correctly in PowerShell 5.1 / conhost. Both the console encoder
# and the PowerShell output encoder must be set before any Write calls.
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
$OutputEncoding            = [System.Text.Encoding]::UTF8

# =============================================================================
# Layout Constants
# =============================================================================
# The panel spans the full console width minus one column to prevent spurious
# scroll events that occur when a WriteLine call wraps at the rightmost column.
$_conW   = $Host.UI.RawUI.WindowSize.Width
$PANEL_W = [math]::Max(72, $_conW - 1)
$INNER_W = $PANEL_W - 4  # Usable content width: border(1) + space(1) + content + space(1) + border(1)

# Color palette
$C = @{
    Border      = [ConsoleColor]::DarkGray
    HeaderBg    = [ConsoleColor]::DarkBlue
    HeaderFg    = [ConsoleColor]::Cyan
    AccentFg    = [ConsoleColor]::Cyan
    White       = [ConsoleColor]::White
    Gray        = [ConsoleColor]::Gray
    Green       = [ConsoleColor]::Green
    Yellow      = [ConsoleColor]::Yellow
    Red         = [ConsoleColor]::Red
    BarFill     = [ConsoleColor]::DarkYellow
    BarEmpty    = [ConsoleColor]::DarkGray
    Label       = [ConsoleColor]::DarkCyan
    Value       = [ConsoleColor]::White
    Success     = [ConsoleColor]::Green
    Warn        = [ConsoleColor]::Yellow
    Error       = [ConsoleColor]::Red
    Dim         = [ConsoleColor]::DarkGray
    SpinnerFg   = [ConsoleColor]::DarkCyan
    PhaseFg     = [ConsoleColor]::Cyan
    StatusFg    = [ConsoleColor]::White
    DetailFg    = [ConsoleColor]::DarkGray
    PctFg       = [ConsoleColor]::Yellow
    VersionFg   = [ConsoleColor]::Green
    PathFg      = [ConsoleColor]::Yellow
    SourceFg    = [ConsoleColor]::DarkGray
}

# Box-drawing characters (CP437 / Windows console safe)
$B = @{
    TL = [char]0x250C  # top-left corner
    TR = [char]0x2510  # top-right corner
    BL = [char]0x2514  # bottom-left corner
    BR = [char]0x2518  # bottom-right corner
    H  = [char]0x2500  # horizontal line
    V  = [char]0x2502  # vertical line
    ML = [char]0x251C  # mid-left tee
    MR = [char]0x2524  # mid-right tee
    BF = [char]0x2022  # black circle
    BH = [char]0x2593  # dark shade (bar medium)
    BE = [char]0x00B7  # middle dot
    DT = [char]0x203A  # ›  single right angle quotation (bullet)
    AR = [char]0x00BB  # »  right double angle quotation (prompt arrow)
    CK = '+'           # + check
    XX = '-'           # - cross
    IN = [char]0x003E  # >  greater-than (info bullet)
}


# =============================================================================
# Primitive Output Helpers
# =============================================================================
# Low-level console write wrappers that temporarily swap the foreground color,
# emit text, then restore the previous color. Write-C stays on the same line;
# Write-CL appends a newline.
function Set-XY([int]$x, [int]$y) {
    [Console]::SetCursorPosition($x, $y)
}

function Write-C([ConsoleColor]$fg, [string]$text) {
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $fg
    [Console]::Write($text)
    [Console]::ForegroundColor = $prev
}

function Write-CL([ConsoleColor]$fg, [string]$text) {
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = $fg
    [Console]::WriteLine($text)
    [Console]::ForegroundColor = $prev
}

# =============================================================================
# Panel Drawing Primitives
# =============================================================================
# Helper functions that compose the bordered panel frame. Draw-HLine renders a
# full-width horizontal rule using the supplied corner characters. Draw-Row
# truncates or right-pads content to fit exactly within the inner width and
# wraps it in vertical border characters.
function Draw-HLine([char]$left, [char]$right) {
    $inner = $B.H -as [string]
    Write-CL $C.Border ("$left" + ($inner * ($PANEL_W - 2)) + "$right")
}

function Draw-Row([string]$content, [ConsoleColor]$fg = [ConsoleColor]::White) {
    # Clip or right-pad $content to exactly $INNER_W characters, then render
    # a full-width bordered row with the specified foreground color.
    $padded = if ($content.Length -gt $INNER_W) {
        $content.Substring(0, $INNER_W)
    } else {
        $content.PadRight($INNER_W)
    }
    Write-C $C.Border ("$($B.V) ")
    Write-C $fg $padded
    Write-CL $C.Border (" $($B.V)")
}

function Draw-BlankRow { Draw-Row "" }

function Draw-Separator {
    $inner = $B.H -as [string]
    Write-CL $C.Border ("$($B.ML)" + ($inner * ($PANEL_W - 2)) + "$($B.MR)")
}

function Draw-KeyVal([string]$label, [string]$value, [ConsoleColor]$valFg = [ConsoleColor]::White) {
    $lbl = $label.PadRight(14)
    $available = $INNER_W - $lbl.Length - 2
    $val = if ($value.Length -gt $available) { $value.Substring(0, $available) } else { $value }
    $line = $lbl + ': ' + $val
    $padded = $line.PadRight($INNER_W)

    Write-C $C.Border ("$($B.V) ")
    Write-C $C.Label $lbl
    Write-C $C.Border ": "
    Write-C $valFg $val
    $remaining = $INNER_W - ($lbl.Length + 2 + $val.Length)
    if ($remaining -gt 0) { Write-C $C.White (' ' * $remaining) }
    Write-CL $C.Border (" $($B.V)")
}

# =============================================================================
# Header Banner
# =============================================================================
# Renders the static information panel showing the tool title, toolchain
# version, installation path, and upstream source. Called once at startup;
# the live dashboard is drawn immediately below it.
function Draw-Header([switch]$Redraw) {
    # On the initial draw, emit a blank line above the top border so the panel
    # does not start flush at row 0. On a redraw (in-place overwrite), skip it
    # so the panel stays anchored to the same rows.
    if (-not $Redraw) { Write-CL $C.Border "" }

    Draw-HLine $B.TL $B.TR

    # Title row - centered inside panel
    $title    = "AUTO GCC INSTALLER  v2.0"
    $titlePad = $INNER_W - $title.Length
    $tLeft    = [math]::Floor($titlePad / 2)
    $tRight   = $titlePad - $tLeft
    $titleCentered = (' ' * $tLeft) + $title + (' ' * $tRight)

    Write-C $C.Border ("$($B.V) ")
    Write-C $C.AccentFg $titleCentered
    Write-CL $C.Border (" $($B.V)")

    # Subtitle centered
    $sub      = "WinLibs MinGW-w64 Toolchain"
    $subPad   = $INNER_W - $sub.Length
    $sLeft    = [math]::Floor($subPad / 2)
    $sRight   = $subPad - $sLeft
    $subCentered = (' ' * $sLeft) + $sub + (' ' * $sRight)

    Write-C $C.Border ("$($B.V) ")
    Write-C $C.Gray $subCentered
    Write-CL $C.Border (" $($B.V)")

    Draw-Separator

    # Info rows — GCC version is populated after release resolution; a
    # placeholder is shown if the header is drawn before resolution completes.
    $displayVer = if ($script:ResolvedVersion) { $script:ResolvedVersion } else { "Resolving latest release..." }
    Draw-KeyVal "GCC"      $displayVer                                $C.VersionFg
    Draw-KeyVal "Install"  "C:\mingw64"                               $C.PathFg
    Draw-KeyVal "Source"   "github.com/brechtsanders/winlibs_mingw"   $C.SourceFg

    Draw-Separator
}

# =============================================================================
# Live Dashboard
# =============================================================================
# Occupies a fixed region directly below the header and is redrawn in-place
# on every progress update without scrolling the terminal.
#
# Row layout (relative to $script:DashY):
#   0     ─ Phase separator
#   1     │ Phase label + spinner
#   2     ─ Separator
#   3     │ Status message
#   4     │ Detail / transfer-speed line
#   5     │ Progress bar
#   6     │ Percentage / indeterminate indicator
#   7     ─ Log separator
#   8…N   │ Scrolling log entries  ($script:MaxLogLines rows)
#   N+1   ╰ Bottom border

$script:DashY       = 0
$script:DashH       = 0
$script:LastConW    = $Host.UI.RawUI.WindowSize.Width
$script:LastStatus  = ""
$script:LastDetail  = ""
$script:LastPct     = 0
$script:LastPhase   = ""
$script:LogLines    = [System.Collections.Generic.List[object]]::new()
$script:MaxLogLines = 5
$script:SpinFrame   = 0
# Synchronized 8-frame Braille spinner arrays that produce a chasing-dot effect.
# SpinRing: Seven-dot ring with one absent dot — the gap advances each frame.
$script:SpinRing = @([char]0x28FE, [char]0x28F7, [char]0x28EF, [char]0x28DF, [char]0x287F, [char]0x28BF, [char]0x28FB, [char]0x28FD)
# SpinDot: Single accent dot that fills the gap, completing the illusion of motion.
$script:SpinDot  = @([char]0x2801, [char]0x2808, [char]0x2810, [char]0x2820, [char]0x2880, [char]0x2840, [char]0x2804, [char]0x2802)


# Records the cursor row immediately after the header, then pre-allocates the
# required number of blank lines so that subsequent in-place redraws never
# push content below the reserved dashboard region.
function Init-Dashboard {
    $script:DashY = [Console]::CursorTop
    # Dashboard layout:
    #   0  ─ phase separator
    #   1  │ phase label row
    #   2  ─ separator
    #   3  │ status row
    #   4  │ detail row
    #   5  │ progress bar row
    #   6  │ pct / speed row
    #   7  ─ separator
    #   8..12  log rows (MaxLogLines)
    #   last ╰ bottom border
    $script:DashH = 1 + 1 + 1 + 1 + 1 + 1 + 1 + 1 + $script:MaxLogLines + 1
    # Emit blank lines to reserve the dashboard region in the console buffer.
    for ($i = 0; $i -lt $script:DashH; $i++) { [Console]::WriteLine() }
}

function Render-Dashboard {
    param(
        [string]$Phase  = $script:LastPhase,
        [string]$Status = $script:LastStatus,
        [string]$Detail = $script:LastDetail,
        [int]   $Pct    = $script:LastPct,
        [switch]$Spin
    )
    $script:LastPhase  = $Phase
    $script:LastStatus = $Status
    $script:LastDetail = $Detail
    $script:LastPct    = $Pct

    # Responsive resize: when the console width changes, clear the screen and
    # redraw the header and dashboard at the new dimensions to avoid layout
    # corruption caused by stale column calculations.
    $currentW = $Host.UI.RawUI.WindowSize.Width
    if ($currentW -ne $script:LastConW -and $currentW -gt 0) {
        $script:LastConW = $currentW
        Set-Variable -Name PANEL_W -Value ([math]::Max(72, $currentW - 1)) -Scope Script
        Set-Variable -Name INNER_W -Value ($PANEL_W - 4) -Scope Script
        [Console]::Clear()
        Draw-Header
        $script:DashY = [Console]::CursorTop
        for ($i = 0; $i -lt $script:DashH; $i++) { [Console]::WriteLine() }
    }

    $row = $script:DashY

    # ── Phase header ─────────────────────────────────────────────────────────
    Set-XY 0 $row
    Draw-Separator
    $row++

    Set-XY 0 $row
    # Spinner slot is always 4 chars: 3 spaces + 1 char for spinner
    $spinSlot   = 4
    $phaseAvail = $INNER_W - $spinSlot
    $phaseTxt   = if ($Phase.Length -gt $phaseAvail) { $Phase.Substring(0, $phaseAvail) } else { $Phase.PadRight($phaseAvail) }

    Write-C  $C.Border  ("$($B.V) ")
    Write-C  $C.Border  "   "        # 3-character padding buffer
    Write-C  $C.PhaseFg  (" " + $phaseTxt)
    Write-CL $C.Border  (" $($B.V)")
    $row++

    Set-XY 0 $row
    Draw-Separator
    $row++

    # ── Status ───────────────────────────────────────────────────────────────
    Set-XY 0 $row
    $statusStr = "  $($B.AR) $Status"
    Draw-Row $statusStr $C.StatusFg
    $row++

    # ── Detail + Percentage (Safe Alignment - Fixed Border Gap) ──────────────
    Set-XY 0 $row

    if ($Pct -ge 0) {
        $detailText = if ($Detail) { $Detail } else { "" }
        $pctText    = "$Pct%"
        
        # Left side gets 4 spaces padding; Right side has percentage
        $leftBase   = "    $detailText"
        
        # Total usable space between borders is exactly $INNER_W
        $maxLeftSpace = $INNER_W - $pctText.Length
        
        if ($leftBase.Length -gt $maxLeftSpace) {
            $leftBase = $leftBase.Substring(0, $maxLeftSpace - 3) + "..."
        }
        
        # Pad the left side so that string length + percentage length exactly equals $INNER_W
        $leftPadded = $leftBase.PadRight($maxLeftSpace)

        Write-C  $C.Border ("$($B.V) ")
        Write-C  $C.DetailFg $leftPadded
        Write-C  $C.PctFg $pctText
        Write-CL $C.Border (" $($B.V)")
    }
    $row++

    # ── Progress bar ─────────────
    Set-XY 0 $row
    $barWidth = $INNER_W
    if ($Pct -ge 0) {
        $filled = [math]::Min($barWidth, [int](($barWidth * $Pct) / 100))
        $empty  = $barWidth - $filled
        Write-C  $C.Border   ("$($B.V) ")
        if ($filled -gt 0) { Write-C $C.BarFill  (([string]$B.BF) * $filled) }
        if ($empty  -gt 0) { Write-C $C.BarEmpty (([string]$B.BE) * $empty)  }
        Write-CL $C.Border   (" $($B.V)")
    } else {
        Draw-BlankRow
    }
    $row++

    # ── Log separator ────────────────────────────────────────────────────────
    Set-XY 0 $row
    Draw-Separator
    $row++

    # ── Log lines ────────────────────────────────────────────────────────────
    $logStart = $row
    $displayed = @($script:LogLines)
    if ($displayed.Count -gt $script:MaxLogLines) {
        $displayed = $displayed[($displayed.Count - $script:MaxLogLines)..($displayed.Count - 1)]
    }
    for ($li = 0; $li -lt $script:MaxLogLines; $li++) {
        Set-XY 0 ($row + $li)
        if ($li -lt $displayed.Count) {
            $entry  = $displayed[$li]
            $icon   = $entry.Icon
            $msg    = $entry.Msg
            $fg     = $entry.Fg
            $lineStr = "  $icon  $msg"
            Draw-Row $lineStr $fg
        } else {
            Draw-BlankRow
        }
    }
    $row += $script:MaxLogLines

    # ── Bottom border ────────────────────────────────────────────────────────
    Set-XY 0 $row
    Draw-HLine $B.BL $B.BR
}

function Add-Log([string]$msg, [string]$icon = "$($B.DT)", [ConsoleColor]$fg = [ConsoleColor]::DarkGray) {
    $script:LogLines.Add([PSCustomObject]@{ Icon = $icon; Msg = $msg; Fg = $fg }) | Out-Null
    Render-Dashboard
}

function Add-LogOK([string]$msg)   { Add-Log $msg '+' $C.Success }
function Add-LogWarn([string]$msg) { Add-Log $msg '!' $C.Warn }
function Add-LogErr([string]$msg)  { Add-Log $msg '-' $C.Error }
function Add-LogInfo([string]$msg) { Add-Log $msg ([char]0x003E) $C.AccentFg }

# =============================================================================
# Final Result Screen
# =============================================================================
# Replaces the live dashboard with a static success or failure summary panel.
# The most recent log entries are displayed beneath the panel so the operator
# can review the outcome without scrolling. After rendering, the user is
# prompted to press Enter before the terminal window closes.
function Draw-Final([bool]$success, [string]$binPath, [string]$elapsed) {
    $row = $script:DashY

    Set-XY 0 $row
    Draw-Separator
    $row++

    Set-XY 0 $row
    if ($success) {
        Draw-Row "  $($B.CK)  Installation Complete!" $C.Success
    } else {
        Draw-Row "  $($B.XX)  Installation Failed" $C.Error
    }
    $row++

    Set-XY 0 $row
    Draw-Separator
    $row++

    if ($success) {
        Set-XY 0 $row
        Draw-KeyVal "GCC binary" "$binPath\gcc.exe" $C.PathFg
        $row++

        Set-XY 0 $row
        Draw-KeyVal "Duration" $elapsed $C.PctFg
        $row++

        Set-XY 0 $row
        Draw-BlankRow
        $row++

        Set-XY 0 $row
        Draw-Row "  Restart PowerShell, then verify:" $C.Yellow
        $row++

        Set-XY 0 $row
        Draw-Row "    gcc --version" $C.Green
        $row++

        Set-XY 0 $row
        Draw-Row "    g++ --version" $C.Green
        $row++
    } else {
        Set-XY 0 $row
        Draw-Row "  Check your internet connection and retry." $C.Yellow
        $row++
        $row++
    }

    # Pad to log area
    $logAreaStart = $script:DashY + 8
    while ($row -lt $logAreaStart) {
        Set-XY 0 $row
        Draw-BlankRow
        $row++
    }

    Set-XY 0 $row; Draw-Separator; $row++
    for ($li = 0; $li -lt $script:MaxLogLines; $li++) {
        $entry = if ($li -lt $script:LogLines.Count) {
            $script:LogLines[$script:LogLines.Count - $script:MaxLogLines + $li]
        } else { $null }
        Set-XY 0 ($row + $li)
        if ($null -ne $entry) {
            Draw-Row "  $($entry.Icon)  $($entry.Msg)" $entry.Fg
        } else {
            Draw-BlankRow
        }
    }
    $row += $script:MaxLogLines
    Set-XY 0 $row
    Draw-HLine $B.BL $B.BR
    $row++

    # Position the cursor below the panel.
    Set-XY 0 $row
    [Console]::CursorVisible = $true
    [Console]::WriteLine()
}

# =============================================================================
# Progress Update Entry Point
# =============================================================================
# Thin wrapper around Render-Dashboard kept for call-site clarity.
# Tick-Spinner writes only the spinner character at its fixed console cell and
# is called on the main thread, so there are no concurrency concerns.
function Tick-Spinner {
    $frame = $script:SpinFrame % 8
    $script:SpinFrame++
    
    $ringChar = $script:SpinRing[$frame]
    
    $savedX = [Console]::CursorLeft
    $savedY = [Console]::CursorTop
    
    # Write only the spinning ring character at its fixed column (column 3,
    # phase label row). The saved cursor position is restored afterwards so
    # subsequent output continues from the correct location.
    [Console]::SetCursorPosition(3, $script:DashY + 1)
    $prev = [Console]::ForegroundColor
    [Console]::ForegroundColor = [ConsoleColor]::DarkYellow
    [Console]::Write($ringChar)
    
    # Restore the cursor to its position before this call.
    [Console]::ForegroundColor = $prev
    [Console]::SetCursorPosition($savedX, $savedY)
}

function Update-Progress([string]$phase, [string]$status, [string]$detail, [int]$pct, [switch]$Spin) {
    Render-Dashboard -Phase $phase -Status $status -Detail $detail -Pct $pct -Spin:$Spin
}

# =============================================================================
# Startup Rendering
# =============================================================================
# Draws the static header banner, initialises the dashboard region, and
# renders the initial "Initializing" state before any work begins.
$script:ResolvedVersion = $null   # Populated after GitHub API resolution
Draw-Header
Init-Dashboard
Render-Dashboard -Phase "Initializing" -Status "Starting up..." -Detail "" -Pct 0

# =============================================================================
# Installer Configuration
# =============================================================================
# Fixed paths and retry policy. The toolchain URL, version string, and SHA-256
# hash are resolved dynamically at runtime from the GitHub Releases API so the
# script always installs the latest available WinLibs build without requiring
# any manual updates to this file.
$InstallDir = "C:\mingw64"
$BinPath    = "$InstallDir\mingw64\bin"
$MaxRetries = 3
$ZipFile    = "$env:TEMP\winlibs.zip"
$Aria2Exe   = "$env:TEMP\aria2c.exe"
$Aria2Zip   = "$env:TEMP\aria2.zip"
$Aria2Url   = "https://github.com/aria2/aria2/releases/download/release-1.37.0/aria2-1.37.0-win-64bit-build1.zip"

[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
$totalSw = [System.Diagnostics.Stopwatch]::StartNew()

# =============================================================================
# Dynamic Release Resolution
# =============================================================================
# Queries the GitHub Releases API for the latest WinLibs MinGW-w64 build,
# selects the x86_64 POSIX SEH UCRT ZIP asset, and retrieves the corresponding
# SHA-256 hash from the accompanying .sha256 file. The installer proceeds with
# these values so it always installs the most recent available toolchain.
Update-Progress "Resolving" "Querying GitHub Releases API..." "Fetching latest WinLibs release metadata" 2 -Spin

try {
    $apiUrl   = "https://api.github.com/repos/brechtsanders/winlibs_mingw/releases/latest"
    $headers  = @{ 'User-Agent' = 'shams_gcc-installer/2.0'; 'Accept' = 'application/vnd.github+json' }
    $release  = Invoke-RestMethod -Uri $apiUrl -Headers $headers -ErrorAction Stop

    # Select the x86_64 / POSIX / SEH / UCRT ZIP asset.
    $asset = $release.assets | Where-Object {
        $_.name -match 'x86_64' -and
        $_.name -match 'posix'  -and
        $_.name -match 'seh'    -and
        $_.name -match 'ucrt'   -and
        $_.name -match '\.zip$'
    } | Select-Object -First 1

    if (-not $asset) {
        throw "No matching x86_64-posix-seh-ucrt ZIP asset found in the latest release."
    }

    $Url = $asset.browser_download_url

    # Extract the GCC version number from the asset filename (e.g. gcc-16.1.0).
    $versionMatch = [regex]::Match($asset.name, 'gcc-([\d.]+)')
    $GccVersion   = if ($versionMatch.Success) { $versionMatch.Groups[1].Value } else { $release.tag_name }

    Add-LogInfo "Latest release: GCC $GccVersion  ($($asset.name))"

    # Fetch the SHA-256 hash from the companion .sha256 file.
    Update-Progress "Resolving" "Fetching SHA-256 checksum..." "Downloading integrity file for $($asset.name)" 4 -Spin

    $sha256Asset = $release.assets | Where-Object { $_.name -eq ($asset.name + '.sha256') } | Select-Object -First 1
    if ($sha256Asset) {
        # Use WebClient to ensure the response is decoded as a UTF-8 string.
        # Invoke-WebRequest.Content returns a byte[] on PS 5.1 for some responses,
        # which causes the hash to be garbled when cast to string.
        $wc = New-Object System.Net.WebClient
        $wc.Headers.Add('User-Agent', 'shams_gcc-installer/2.0')
        $sha256Raw    = $wc.DownloadString($sha256Asset.browser_download_url)
        $wc.Dispose()
        # The file format is "<hash>  <filename>" -- extract the first whitespace-delimited token.
        $ExpectedHash = ($sha256Raw -split '\s+')[0].Trim().ToUpper()
        Add-LogInfo "SHA-256: $($ExpectedHash.Substring(0,16))..."
    } else {
        # No companion hash file -- integrity verification will be skipped.
        $ExpectedHash = $null
        Add-LogWarn "No .sha256 asset found - checksum verification will be skipped"
    }
} catch {
    Add-LogErr "Release resolution failed: $_"
    Draw-Final $false "" ""
}

# Update the header panel to reflect the resolved version.
# Overwrite the header region in-place, then restore the dashboard cursor anchor.
$script:ResolvedVersion = "$GccVersion  (x86_64 / POSIX / SEH / UCRT)"
$savedDashY = $script:DashY
[Console]::SetCursorPosition(0, 1)
Draw-Header -Redraw
$script:DashY = $savedDashY

# =============================================================================
# Pre-flight: Existing GCC Detection
# =============================================================================
# Searches the current PATH for an existing gcc binary. If one is found, the
# installer displays the discovered location and version string, then exits
# cleanly without modifying the system.
Update-Progress "Pre-flight Check" "Scanning PATH for existing GCC..." "" 10 -Spin

$existingGcc = Get-Command gcc -ErrorAction SilentlyContinue
if ($existingGcc) {
    $gccDir     = Split-Path -Path $existingGcc.Path
    $gccVersion = (& gcc --version 2>&1 | Select-Object -First 1).Trim()
    $totalSw.Stop()

    # ── Render an "already installed" final screen ───────────────────────────
    $colSuccess    = $C.Success
    $colPathFg     = $C.PathFg
    $colVersionFg  = $C.VersionFg
    $colYellow     = $C.Yellow

    # Erase every row that Init-Dashboard pre-reserved to ensure nothing bleeds
    # below the bottom border of the panel we are about to draw.
    $blankLine = ' ' * $PANEL_W
    for ($r = $script:DashY; $r -lt ($script:DashY + $script:DashH); $r++) {
        Set-XY 0 $r
        [Console]::Write($blankLine)
    }

    $row = $script:DashY

    Set-XY 0 $row
    Draw-Separator
    $row++

    Set-XY 0 $row
    Draw-Row "  $($B.CK)  GCC Already Installed - Skipping" $colSuccess
    $row++

    Set-XY 0 $row
    Draw-Separator
    $row++

    Set-XY 0 $row
    Draw-KeyVal "GCC binary" "$gccDir\gcc.exe" $colPathFg
    $row++

    Set-XY 0 $row
    Draw-KeyVal "Version" $gccVersion $colVersionFg
    $row++

    Set-XY 0 $row
    Draw-BlankRow
    $row++

    Set-XY 0 $row
    Draw-Row "  Nothing to do - GCC is already on your PATH." $colYellow
    $row++

    Set-XY 0 $row
    Draw-HLine $B.BL $B.BR
    $row++

    # Place the cursor below the panel.
    Set-XY 0 $row
    [Console]::CursorVisible = $true
    [Console]::WriteLine()
    exit 0
}

Add-LogInfo "No GCC on PATH - starting fresh install"

# =============================================================================
# Download and Integrity Verification Loop
# =============================================================================
# Attempts up to $MaxRetries download cycles. Each cycle tries three
# progressively conservative download strategies before validating the
# archive against the expected SHA-256 digest. A successful, verified download
# breaks out of the loop; a failed digest check removes the corrupt file and
# retries from the beginning.
for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {

    if ($attempt -gt 1) {
        Add-LogWarn "Retry attempt $attempt of $MaxRetries"
    }

    $downloaded = $false

    # -------------------------------------------------------------------------
    # Strategy 1: aria2c — 16 Parallel Connections
    # -------------------------------------------------------------------------
    # aria2c is bootstrapped on first use by downloading its portable release
    # ZIP from GitHub, extracting the executable, and caching it in %TEMP% for
    # subsequent runs.
    Update-Progress "Download" "Checking for aria2c accelerator..." "Looking in temp cache" 5 -Spin

    if (-not (Test-Path $Aria2Exe)) {
        Update-Progress "Download" "Bootstrapping aria2c..." "Fetching portable release from GitHub" 8 -Spin
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
            Add-LogWarn "Could not fetch aria2c  -  will try chunk downloader"
        }
    }

    if (Test-Path $Aria2Exe) {
        Update-Progress "Download" "Launching aria2c with 16 connections..." "Opening connection to GitHub releases" 10 -Spin
        Add-LogInfo "Using aria2c  -  16 parallel streams"
        try {
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName  = $Aria2Exe
            $psi.Arguments = "--split=16 --max-connection-per-server=16 --min-split-size=5M " +
                             "--file-allocation=none --console-log-level=warn " +
                             "--summary-interval=1 " +
                             "--dir=`"$env:TEMP`" --out=winlibs.zip `"$Url`""
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError  = $true
            $psi.UseShellExecute  = $false
            $psi.CreateNoWindow   = $true

            $proc = [System.Diagnostics.Process]::Start($psi)
            $stderrJob = $proc.StandardError.ReadToEndAsync()

            # Read aria2c stdout asynchronously so the spinner can advance on
            # every loop iteration regardless of whether a progress line arrived.
            $lineTask = $proc.StandardOutput.ReadLineAsync()
            while (-not $proc.HasExited -or $lineTask -ne $null) {
                # Advance the spinner on every loop tick (~80 ms)
                Tick-Spinner

                if ($lineTask -ne $null -and $lineTask.IsCompleted) {
                    $line = $lineTask.Result
                    $lineTask = if (-not $proc.HasExited -or $proc.StandardOutput.Peek() -ge 0) {
                        $proc.StandardOutput.ReadLineAsync()
                    } else { $null }

                    if ($line -match '\[#\w+\s+([\d.]+\w+)/([\d.]+\w+)\((\d+)%\).*DL:([\d.]+\w+)') {
                        $pct   = [int]$Matches[3]
                        $done  = $Matches[1]
                        $total = $Matches[2]
                        $speed = $Matches[4]
                        $detail = "$done / $total | $speed/s"
                        Update-Progress "Download" "Downloading GCC toolchain..." "$done / $total  |  $speed/s" $pct -Spin
                    } elseif ($line -eq $null) {
                        break  # EOF
                    }
                } else {
                    Start-Sleep -Milliseconds 80
                }
            }
            $proc.WaitForExit()

            $stderrText = $stderrJob.Result.Trim()
            if ($proc.ExitCode -eq 0 -and (Test-Path $ZipFile)) {
                $downloaded = $true
                Add-LogOK "aria2c finished  -  archive received"
            } else {
                Add-LogWarn "aria2c exited with code $($proc.ExitCode)  -  trying fallback"
                if ($stderrText) { Add-LogWarn $stderrText.Substring(0, [math]::Min(60, $stderrText.Length)) }
                if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
            }
        } catch {
            Add-LogWarn "aria2c threw an error  -  falling back to chunk downloader"
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        } finally {
            Remove-Item $Aria2Exe -Force -ErrorAction SilentlyContinue
        }
    } else {
        Add-LogWarn "aria2c not available  -  switching to chunk downloader"
    }

    # -------------------------------------------------------------------------
    # Strategy 2: Parallel Chunk Downloader — 8 Workers
    # -------------------------------------------------------------------------
    # Issues a HEAD request to determine file size and final redirect URL,
    # then spawns 8 background jobs each responsible for a distinct byte range.
    # Chunks are concatenated in order after all jobs complete.
    if (-not $downloaded) {
        Add-LogInfo "Launching 8 parallel HTTP range workers"
        Update-Progress "Download" "Resolving file size via HEAD request..." "Probing GitHub release endpoint" 12 -Spin

        $chunkFiles = $null
        $jobs       = $null
        try {
            $head = [System.Net.HttpWebRequest]::Create($Url)
            $head.Method = 'HEAD'
            $head.UserAgent = 'shams_gcc-installer/2.0'
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
                    $req.UserAgent = 'shams_gcc-installer/2.0'
                    $req.AllowAutoRedirect = $true
                    $req.KeepAlive = $true
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

            $dlSw = [System.Diagnostics.Stopwatch]::StartNew()
            $uiSw = [System.Diagnostics.Stopwatch]::StartNew()
            while ($jobs | Where-Object { $_.State -eq 'Running' }) {
                if ($uiSw.ElapsedMilliseconds -ge 80) {
                    $doneBytes = ($chunkFiles | ForEach-Object {
                        if (Test-Path $_) { (Get-Item $_).Length } else { 0 }
                    } | Measure-Object -Sum).Sum
                    $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                    $speedMBps  = ($doneBytes / 1MB) / $elapsedSec
                    $speedStr   = $speedMBps.ToString('N1')
                    $doneMB     = '{0:N1}' -f ($doneBytes / 1MB)
                    $totalMB    = '{0:N1}' -f ($totalBytes / 1MB)
                    $pct        = [math]::Min(100, [int](100L * $doneBytes / $totalBytes))
                    $detail = "$doneMB / $totalMB | $speedStr MB/s"
                    $activeJobs = ($jobs | Where-Object { $_.State -eq 'Running' }).Count
                    Update-Progress "Download" "Downloading  -  $activeJobs of 8 workers active..." $detail $pct -Spin
                    $uiSw.Restart()
                }
                Start-Sleep -Milliseconds 50
            }

            $failed = $jobs | Where-Object { $_.State -ne 'Completed' }
            $jobs | Remove-Job -Force
            if ($failed) { throw "One or more chunk downloads failed." }

            Update-Progress "Download" "Assembling chunks into archive..." "Concatenating $numChunks segments" -1 -Spin
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

            $downloaded = $true
            Add-LogOK "Chunk download complete  -  all $numChunks segments received"
        } catch {
            Add-LogWarn "Chunk downloader failed  -  falling back to single-stream"
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
            if ($chunkFiles) { $chunkFiles | ForEach-Object { Remove-Item $_ -Force -ErrorAction SilentlyContinue } }
            if ($jobs)       { $jobs | Remove-Job -Force -ErrorAction SilentlyContinue }
        }
    }

    # -------------------------------------------------------------------------
    # Strategy 3: Single-Stream Fallback
    # -------------------------------------------------------------------------
    # Standard sequential download using HttpWebRequest with an 8 MB read
    # buffer. Used when both parallel strategies are unavailable or failed.
    if (-not $downloaded) {
        Add-LogInfo "Single-stream mode - downloading sequentially"
        Update-Progress "Download" "Opening single-stream connection..." "Establishing HTTP connection" 5 -Spin

        $request = [System.Net.HttpWebRequest]::Create($Url)
        $request.UserAgent        = 'shams_gcc-installer/2.0'
        $request.AllowAutoRedirect = $true
        $request.KeepAlive        = $true
        $request.Timeout          = 60000
        $request.ReadWriteTimeout = 30000

        try {
            $response   = $request.GetResponse()
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

                    if ($uiSw.ElapsedMilliseconds -ge 80) {
                        $elapsedSec = [math]::Max(0.001, $dlSw.Elapsed.TotalSeconds)
                        $speedMBps  = ($totalRead / 1MB) / $elapsedSec
                        $doneMB     = '{0:N1}' -f ($totalRead / 1MB)

                        $speedStr = $speedMBps.ToString('N1')
                        if ($totalBytes -gt 0) {
                            $pct     = [math]::Min(100, [int](100L * $totalRead / $totalBytes))
                            $totalMB = '{0:N1}' -f ($totalBytes / 1MB)
                            $detail = "$doneMB / $totalMB | $speedStr MB/s"
                            Update-Progress "Download" "Downloading GCC toolchain..." $detail $pct -Spin
                        } else {
                            $detail = $doneMB + " MB received  |  " + $speedStr + " MB/s  (size unknown)"
                            Update-Progress "Download" "Downloading GCC toolchain..." $detail -1 -Spin
                        }
                        $uiSw.Restart()
                    }
                }
            } finally {
                $fileStream.Dispose()
                $readStream.Dispose()
                $response.Dispose()
            }
            $downloaded = $true
            $finalMB = '{0:N1}' -f ($totalRead / 1MB)
            Add-LogOK "Download complete  -  $finalMB MB received"
        } catch {
            Add-LogErr "All download strategies failed: $_"
            if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }
        }
    }  # end Strategy 3 if block

    # -------------------------------------------------------------------------
    # SHA-256 Integrity Verification
    # -------------------------------------------------------------------------
    # Computes the SHA-256 digest of the downloaded archive and compares it
    # against the hash retrieved from the release assets. A mismatch indicates
    # a corrupt or tampered file; the archive is deleted and the retry loop
    # continues. Verification is skipped when no hash file was available.
    if ($ExpectedHash) {
        $archiveMB  = '{0:N1}' -f ((Get-Item $ZipFile).Length / 1MB)
        Update-Progress "Verify" "Computing SHA-256 checksum..." "Hashing $archiveMB MB archive" -1 -Spin

        $actualHash = (Get-FileHash -Path $ZipFile -Algorithm SHA256).Hash
        if ($actualHash -ne $ExpectedHash.ToUpper()) {
            Add-LogErr "Checksum mismatch on attempt $attempt  -  archive may be corrupt"
            Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
            if ($attempt -lt $MaxRetries) { continue }
            Draw-Final $false "" ""
        }
        Add-LogOK "SHA-256 verified  -  archive is intact"
    } else {
        Add-LogWarn "Checksum verification skipped  -  no hash file available for this release"
    }
    break

} # end retry loop

# =============================================================================
# Archive Extraction
# =============================================================================
# Removes any pre-existing installation directory, then extracts the verified
# ZIP archive entry-by-entry. Each target path is validated against the install
# root to guard against zip-slip path traversal attacks.
Update-Progress "Extract" "Scanning archive contents..." "Counting entries before extraction" 0 -Spin

if (Test-Path $InstallDir) {
    Add-LogInfo "Removing old install at $InstallDir"
    Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue
}

Add-Type -AssemblyName System.IO.Compression.FileSystem
$extractOk = $false

try {
    $archive     = [System.IO.Compression.ZipFile]::OpenRead($ZipFile)
    $fileEntries = @($archive.Entries | Where-Object { -not $_.FullName.EndsWith('/') })
    $n = $fileEntries.Count
    $i = 0
    $uiSw = [System.Diagnostics.Stopwatch]::StartNew()

    try {
        foreach ($entry in $fileEntries) {
            $i++
            $relative   = $entry.FullName.Replace('/', [System.IO.Path]::DirectorySeparatorChar)
            $targetPath = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($InstallDir, $relative))
            $installRoot = [System.IO.Path]::GetFullPath($InstallDir)

            if (-not $targetPath.StartsWith($installRoot, [StringComparison]::OrdinalIgnoreCase)) {
                throw "Zip-slip detected: $targetPath"
            }

            $destDir = [System.IO.Path]::GetDirectoryName($targetPath)
            if ($destDir -and -not (Test-Path -LiteralPath $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }

            [System.IO.Compression.ZipFileExtensions]::ExtractToFile($entry, $targetPath, $true)

            Tick-Spinner
            if ($uiSw.ElapsedMilliseconds -ge 200) {
                $pct      = if ($n -gt 0) { [math]::Min(100, [int](100 * $i / $n)) } else { 100 }
                $fileName = [System.IO.Path]::GetFileName($entry.FullName)
                Update-Progress "Extract" "Extracting $i of $n files..." $fileName $pct -Spin
                $uiSw.Restart()
            }
        }
        $extractOk = $true
    } finally {
        $archive.Dispose()
    }
} catch {
    Add-LogErr "Extraction failed: $_"
    if (Test-Path $InstallDir) { Remove-Item $InstallDir -Recurse -Force -ErrorAction SilentlyContinue }
    Remove-Item $ZipFile -Force -ErrorAction SilentlyContinue
    Draw-Final $false "" ""
}

Add-LogOK "Extracted $n files to $InstallDir"
if (Test-Path $ZipFile) { Remove-Item $ZipFile -Force }

# =============================================================================
# PATH Registration
# =============================================================================
# Appends the toolchain binary directory to the current user's persistent PATH
# if it is not already present. The machine-level PATH is left unchanged, and
# a duplicate entry is never added.
Update-Progress "Configure" "Registering toolchain in PATH..." "Writing to user environment registry key" 90 -Spin

$CurrentPath = [Environment]::GetEnvironmentVariable("Path", "User")
if ($CurrentPath -notlike "*$BinPath*") {
    [Environment]::SetEnvironmentVariable("Path", "$CurrentPath;$BinPath", "User")
    Add-LogOK "Toolchain registered in user PATH"
} else {
    Add-LogInfo "PATH already contains $BinPath  -  no change needed"
}

# =============================================================================
# Completion
# =============================================================================
# Stops the global stopwatch, formats the elapsed duration, logs the final
# success message, and renders the static completion screen.
$totalSw.Stop()
$elapsed = $totalSw.Elapsed
$elapsedStr = if ($elapsed.TotalMinutes -ge 1) {
    "$([int]$elapsed.TotalMinutes)m $($elapsed.Seconds)s"
} else {
    $msDigit = $elapsed.Milliseconds.ToString('D3').Substring(0, 1)
    "$($elapsed.Seconds).${msDigit}s"
}

Add-LogOK "All done in $elapsedStr - GCC is ready"

Draw-Final $true $BinPath $elapsedStr
