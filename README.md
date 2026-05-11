# One‑Line GCC (MinGW‑w64) Solution for Windows

This project provides a single PowerShell command to install **GCC / G++ (MinGW‑w64)** on Windows. It is designed for fast setup on new or freshly configured machines—no manual downloads and no PATH guesswork.

## Quick install

Open **Windows Terminal (Admin)** (or regular Windows Terminal; the script will prompt for elevation if required), then run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1 | iex
```

Short link:

```powershell
irm https://bit.ly/shams_gcc | iex
```

## What it does

- **Downloads** the MinGW‑w64 toolchain (GCC 16.1.0) from [winlibs](https://winlibs.com/)
- **Verifies** the download using a SHA‑256 checksum (retries up to 3 times on corruption)
- **Extracts** to `C:\mingw64`
- **Adds** `C:\mingw64\mingw64\bin` to the **User PATH**
- **Cleans up** temporary files
- **Reports** total install time

## Download strategy

The installer tries the following methods in order and falls back automatically:

| Priority | Method | Notes |
|---:|---|---|
| 1 | **aria2c** (16 connections) | Fastest when available |
| 2 | **Parallel chunk download** (PowerShell) | High throughput without extra tooling |
| 3 | **Single stream** (PowerShell) | Most compatible fallback |

## Verify installation

After the script completes, **restart PowerShell**, then run:

```powershell
gcc --version
g++ --version
```

Expected output includes:

```text
gcc (GCC) 16.1.0 ...
```

## Uninstall

To remove GCC/G++ and related toolchain files, run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc_remove.ps1 | iex
```

Short link:

```powershell
irm https://bit.ly/gcc_remove | iex
```

### What the remover does

- Detects common GCC toolchain layouts (WinLibs, MSYS2, TDM‑GCC, and standard MinGW paths)
- Previews planned removals (PATH entries and directories) before changes
- Removes PATH entries from **User** and/or **Machine** scope (Machine scope requires Admin)
- Deletes toolchain folders (e.g. `C:\mingw64`, `C:\msys64`, etc.)
- Broadcasts the environment change so new terminals pick it up

### Remover options

| Flag | Description |
|---|---|
| `-Scope User` | Only clean the User PATH (default: `All`) |
| `-Scope Machine` | Only clean the Machine PATH (requires Admin) |
| `-Scope All` | Clean both User and Machine PATH |
| `-Force` | Skip confirmation prompts |
| `-ExtraPath <paths>` | Extra PATH fragments to force-remove |

## Package details

| Property | Value |
|---|---|
| GCC version | 16.1.0 |
| Toolchain | MinGW‑w64 UCRT (posix, SEH) |
| Architecture | x86_64 |
| Install location | `C:\mingw64` |
| Binary path added to PATH | `C:\mingw64\mingw64\bin` |
| SHA‑256 | `325771F545E89F62C0E1FAFDBF0066CC49E3321AECA7B704C8D065E97A72F2FB` |
| Source | [winlibs by brechtsanders](https://github.com/brechtsanders/winlibs_mingw) |

## Requirements

- Windows 10 or later
- PowerShell 5.1+ or PowerShell 7+
- Internet connection
- ~400 MB free disk space

## Safety and reliability

- **Checksum verification**: SHA‑256 is validated after download; corrupt files are deleted and retried (up to 3 attempts).
- **Path safety**: the installer updates **User PATH** only (no system-wide PATH changes).
- **Cleanup**: temporary files (ZIP, aria2c) are removed after completion.
- **Failure recovery**: partial extractions are cleaned up so reruns start from a known state.

## Demo
**View in fullscreen for better rendering.**

https://github.com/user-attachments/assets/1bef662e-9bb7-40c4-8a27-d560f2700f25


## Author

Made by [Shams](https://github.com/ShamsKabir).

