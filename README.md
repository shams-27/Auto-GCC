# ⚙️ One-Line GCC Soution for Windows

Instantly installs **GCC / G++ (MinGW-w64)** on Windows with a single PowerShell command. No manual downloading, no PATH headaches.

---

## 🚀 Quick Install

Open **PowerShell** (any version) and run:

```powershell
irm https://raw.githubusercontent.com/ShamsKabir/tools/main/shams_gcc.ps1 | iex
```
**Or (Shortened URL)**
```powershell
irm https://smplu.link/shams_gcc | iex
```

> The script will automatically re-launch itself as **Administrator** if needed — just click **Yes** on the UAC prompt.

---

## ✅ What It Does

1. **Downloads** the latest MinGW-w64 toolchain (GCC 16.1.0) from [winlibs](https://winlibs.com/)
2. **Extracts** it to `C:\mingw64`
3. **Adds** `C:\mingw64\mingw64\bin` to your **User PATH** automatically
4. Cleans up the temporary zip file

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
irm https://smplu.link/shams_gcc_remove | iex
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
| **Source** | [winlibs by brechtsanders](https://github.com/brechtsanders/winlibs_mingw) |

---

## 💡 Requirements

- Windows 10 or later
- PowerShell 5.1+ (comes pre-installed) or PowerShell 7+
- Internet connection
- ~400 MB of free disk space

---

## 🛡️ Safety Notes

- The installer only modifies your **User PATH** — not the system-wide PATH.
- Extraction is protected against **zip slip attacks** (files outside the install directory are refused).
- The remover shows a full preview and asks for confirmation before deleting anything.
- No third-party tools or package managers required.

---

## 🧑‍💻 Made by [Shams](https://github.com/ShamsKabir)
