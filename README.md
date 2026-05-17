# shams_gcc — Automated GCC Toolchain Installer for Windows

A single PowerShell command to install the latest GCC/G++ toolchain (WinLibs MinGW-w64) on Windows. Designed for fast, reliable setup on new or freshly configured machines with no manual downloads, no PATH guesswork, and no leftover files.

---

## Quick Install

Open **Windows Terminal** or **PowerShell** (the script self-elevates if Administrator rights are needed), then run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1 | iex
```

Short link:

```powershell
irm https://bit.ly/shams_gcc | iex
```

---

## What It Does

1. **Resolves** the latest WinLibs MinGW-w64 release automatically via the GitHub Releases API — no hardcoded version numbers.
2. **Checks** for an existing GCC installation on the current PATH and exits cleanly if one is found.
3. **Downloads** the x86_64 POSIX SEH UCRT toolchain archive using the fastest available method (see Download Strategies below).
4. **Verifies** the archive against its SHA-256 checksum; retries up to 3 times on corruption or failure.
5. **Extracts** to `C:\mingw64` with zip-slip path traversal protection.
6. **Registers** `C:\mingw64\mingw64\bin` in the current user's PATH — machine-level PATH is never modified.
7. **Cleans up** all temporary files (archive, aria2c binary).
8. **Reports** the resolved GCC version, binary location, and total installation time.

---

## Download Strategies

The installer attempts the following methods in order, falling back automatically on failure:

| Priority | Method | Details |
|---:|---|---|
| 1 | **aria2c** | 16 parallel connections for maximum throughput. The aria2c binary is bootstrapped automatically from its GitHub release and cached in `%TEMP%`. |
| 2 | **Parallel chunk downloader** | 8 concurrent HTTP range-request workers implemented in pure PowerShell. No additional tooling required. |
| 3 | **Single-stream download** | `HttpWebRequest` with an 8 MB buffer. Most compatible fallback for restricted environments. |

---

## Verify Installation

After the script completes, restart PowerShell and run:

```powershell
gcc --version
g++ --version
```

Expected output:

```
gcc (GCC) 16.x.x ...
g++ (GCC) 16.x.x ...
```

---

## Uninstall

To remove the GCC toolchain, run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc_remove.ps1 | iex
```

Short link:

```powershell
irm https://bit.ly/gcc_remove | iex
```

### What the Remover Does

- Detects common GCC toolchain layouts: WinLibs, MSYS2, TDM-GCC, and standard MinGW paths.
- Previews all planned removals (PATH entries and directories) before making any changes.
- Removes PATH entries from User and/or Machine scope (Machine scope requires Administrator).
- Deletes the toolchain directory (e.g. `C:\mingw64`).
- Broadcasts the environment change so new terminal sessions pick it up immediately.

### Remover Options

| Flag | Description |
|---|---|
| `-Scope User` | Remove GCC from the User PATH only (default: `All`) |
| `-Scope Machine` | Remove GCC from the Machine PATH only (requires Administrator) |
| `-Scope All` | Remove GCC from both User and Machine PATH |
| `-Force` | Skip all confirmation prompts |
| `-ExtraPath <paths>` | Force-remove additional PATH fragments |

---

## Toolchain Details

| Property | Value |
|---|---|
| Toolchain | WinLibs MinGW-w64 |
| Variant | x86_64, POSIX threads, SEH exceptions, UCRT runtime |
| GCC version | Resolved at runtime from the latest GitHub release |
| Install location | `C:\mingw64` |
| PATH entry added | `C:\mingw64\mingw64\bin` |
| PATH scope | User only (machine PATH is not modified) |
| Source | [brechtsanders/winlibs_mingw](https://github.com/brechtsanders/winlibs_mingw) |

---

## Requirements

- Windows 10 or Windows 11 (x86_64)
- PowerShell 5.1 or PowerShell 7+
- Active internet connection
- Approximately 400 MB of free disk space

Administrator privileges are required and requested automatically via self-elevation if the session does not already hold them.

---

## Safety and Reliability

**Dynamic version resolution.** The installer queries the GitHub Releases API at runtime to select the latest WinLibs release. The script never needs to be updated to track new GCC versions.

**Checksum verification.** The SHA-256 hash is fetched from the companion `.sha256` asset alongside the archive. If the computed digest does not match, the corrupt file is deleted and the download is retried (up to 3 attempts). Verification is skipped with a warning only when no hash asset is available for a given release.

**Zip-slip protection.** Each archive entry's resolved path is validated against the installation root before extraction. Entries that would write outside `C:\mingw64` cause an immediate, clean abort.

**User PATH only.** The installer writes to the User-scoped PATH registry key. System-wide environment variables are never touched.

**Idempotent.** If GCC is already present on the PATH, the installer detects it, displays the existing location and version, and exits without making any changes.

**Automatic cleanup.** The downloaded archive and the bootstrapped aria2c binary are removed from `%TEMP%` after a successful installation. Partial extractions are cleaned up on failure so subsequent runs always start from a known state.

---

## Author

Made by [Shams](https://github.com/ShamsKabir).
