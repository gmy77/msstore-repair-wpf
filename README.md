# Microsoft Store Repair (WPF) v1.0.0

PowerShell tool with a WPF GUI to repair Microsoft Store update/download issues.

## Features
- Reset Store cache (wsreset)
- Restart Store-related services
- Clear Store LocalCache
- Re-register Microsoft Store
- Re-register all UWP apps
- Diagnostics and logging
- Full repair workflow

## Requirements
- Windows 11
- PowerShell 5.1+ (or PowerShell 7)
- Run as Administrator

## Usage
Open PowerShell as Administrator and run:

```powershell
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass
.\MSStoreRepair.ps1
```

Logs are written to `logs\msstore-repair.log`.
