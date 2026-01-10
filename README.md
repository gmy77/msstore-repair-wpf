# Microsoft Store Repair (WPF) v2.0.0

[![Latest Release](https://img.shields.io/github/v/release/gmy77/msstore-repair-wpf?label=latest)](https://github.com/gmy77/msstore-repair-wpf/releases/latest)

PowerShell tool with a WPF GUI to repair Microsoft Store update/download issues.

## What's New in v2.0.0 🚀

**Performance & Stability**
- ✅ Removed redundant runspace management - faster execution
- ✅ Optimized threading with InvokeAsync
- ✅ Enhanced error handling with comprehensive try-catch blocks
- ✅ Global exception handler for unhandled errors

**Improved Features**
- ✅ Daily log files with timestamps (`msstore-repair_YYYY-MM-DD.log`)
- ✅ Timeout protection for long-running operations (60s for wsreset)
- ✅ Detailed progress tracking every 10% for app repairs
- ✅ Success/failure counters for all operations
- ✅ Enhanced diagnostics with service status and cache details
- ✅ Better UI feedback with message boxes for errors

**Code Quality**
- ✅ PowerShell approved verb-noun naming conventions
- ✅ Improved parameter validation
- ✅ Thread-safe UI updates
- ✅ Modernized code structure

## Features
- Reset Store cache (wsreset) with timeout protection
- Restart Store-related services (5 services monitored)
- Clear Store LocalCache with file counting
- Re-register Microsoft Store packages
- Re-register all UWP apps with detailed progress
- Comprehensive diagnostics (services, packages, cache, processes)
- Full repair workflow with 5-step process
- Daily rotating logs

## Screenshot
![Microsoft Store Repair GUI](immagine.png)

## Requirements
- Windows 11
- PowerShell 5.1+ (or PowerShell 7)
- Run as Administrator

## Usage

### Quick Start
Simply double-click `MSStoreRepair.ps1` or run from PowerShell:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\MSStoreRepair.ps1
```

The script will:
1. Auto-detect if running in STA mode (required for WPF) and relaunch if needed
2. Check for Administrator privileges and prompt to elevate if needed
3. Launch the GUI interface

### Logs
Daily log files are automatically created in:
```
.\logs\msstore-repair_YYYY-MM-DD.log
```

Log format:
```
[2026-01-10 15:30:45] [Info] Starting: Diagnostics
[2026-01-10 15:30:46] [Success] Operation completed
[2026-01-10 15:30:47] [Warning] Service not found
[2026-01-10 15:30:48] [Error] Failed to execute
```

### Troubleshooting
- **Appx cmdlets not available**: Use Windows PowerShell 5.1 instead of PowerShell 7, or import the module:
  ```powershell
  Import-Module Appx -UseWindowsPowerShell
  ```
- **Operation timeout**: wsreset.exe has a 60-second timeout to prevent hanging
- **Check logs**: All operations are logged with detailed error messages

## Download
Grab the latest ZIP from the GitHub Releases page:
https://github.com/gmy77/msstore-repair-wpf/releases

## License
MIT
