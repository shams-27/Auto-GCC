# ⚙️ One-Line GCC Solution for Windows

Instantly installs **GCC / G++ (MinGW-w64)** on Windows with a single PowerShell command. No manual downloading, no PATH headaches.

https://github.com/user-attachments/assets/99c99933-1953-4bfd-bdee-943dbb8b04c0

---

## 🚀 Quick Install

Open **Windows Terminal / PowerShell** (any version), copy the command below and press Enter:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1 | iex
```

**Or (Shortened URL)**

```powershell
irm https://bit.ly/shams_gcc | iex
```

> The script will automatically re-launch itself as **Administrator** if needed — just click **Yes** on the UAC prompt.

---

## ✅ What It Does

1. **Downloads** the MinGW-w64 toolchain (GCC 16.1.0) from [winlibs](https://winlibs.com/) using the fastest available method
2. **Verifies** the download with a SHA-256 checksum — auto-retries up to 3 times if corrupted
3. **Extracts** it to `C:\mingw64`
4. **Adds** `C:\mingw64\mingw64\bin` to your **User PATH** automatically
5. **Cleans up** all temporary files
6. **Reports** total install time on completion

---

## ⚡ Download Speed

The installer tries three strategies in order, falling back automatically if one fails:

| Strategy | Method | Speed |
|---|---|---|
| **1. aria2c** | 16 parallel connections | 🚀 Fastest |
| **2. Parallel chunks** | 8 simultaneous streams (pure PowerShell) | ⚡ Fast |
| **3. Single stream** | 8 MB buffer, optimised fallback | ✅ Reliable |

---

## 🔍 Verify Installation

After the installer finishes, **restart PowerShell**, then run:

```powershell
gcc --version
g++ --version
```

You should see output like:

```
gcc (GCC) 16.1.0 ...
```

---

## 🗑️ Uninstall

To completely remove GCC/G++ and all related toolchain files, run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc_remove.ps1 | iex
```

**Or (Shortened URL)**

```powershell
irm https://bit.ly/gcc_remove | iex
```

The remover will:

1. **Detect** all `gcc.exe` / `g++.exe` locations currently on your PATH
2. **Preview** every PATH entry and toolchain folder it plans to remove — before touching anything
3. **Ask for confirmation** before making any changes (use `-Force` to skip prompts)
4. **Clean up PATH** entries from User and/or Machine scope
5. **Delete toolchain folders** from disk (e.g. `C:\mingw64`, `C:\msys64`, etc.)
6. **Broadcast** an environment change so open terminals pick it up immediately

**Supported toolchains:** WinLibs, MSYS2 (ucrt64, mingw64, mingw32, clang64), TDM-GCC, and most standard MinGW layouts.

### Remover Options

| Flag | Description |
|---|---|
| `-Scope User` | Only clean the User PATH (default: `All`) |
| `-Scope Machine` | Only clean the Machine PATH (requires Admin) |
| `-Scope All` | Clean both User and Machine PATH |
| `-Force` | Skip all confirmation prompts |
| `-ExtraPath <paths>` | Extra PATH fragments to force-remove |

---

## 📦 Package Details

| Property | Value |
|---|---|
| **GCC Version** | 16.1.0 |
| **Toolchain** | MinGW-w64 UCRT (posix, SEH) |
| **Architecture** | x86\_64 |
| **Install Location** | `C:\mingw64` |
| **Binary Path** | `C:\mingw64\mingw64\bin` |
| **SHA-256** | `325771F545E89F62C0E1FAFDBF0066CC49E3321AECA7B704C8D065E97A72F2FB` |
| **Source** | [winlibs by brechtsanders](https://github.com/brechtsanders/winlibs_mingw) |

---

## 💡 Requirements

- Windows 10 or later
- PowerShell 5.1+ (comes pre-installed) or PowerShell 7+
- Internet connection
- ~400 MB of free disk space

---

## 🛡️ Safety & Reliability

- **Checksum verified** — SHA-256 is checked after every download; corrupted files are deleted and retried automatically (up to 3 attempts)
- **Zip slip protection** — files attempting to extract outside `C:\mingw64` are refused
- **Clean failure recovery** — if extraction fails mid-way, the partial install is removed so the next run always starts fresh
- **User PATH only** — the installer never touches the system-wide PATH
- **No leftovers** — temporary files (ZIP, aria2c) are deleted after use
- **No third-party tools or package managers required**

---

## 🧑‍💻 Made by [Shams](https://github.com/ShamsKabir)
