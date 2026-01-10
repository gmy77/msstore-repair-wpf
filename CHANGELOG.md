# Changelog

## [2.0.0] - 2026-01-10

### 🚀 Performance Improvements
- Removed redundant runspace management in BackgroundWorker (significant performance boost)
- Optimized UI threading with InvokeAsync and proper dispatcher priorities
- Improved memory management by eliminating runspace creation/disposal cycles

### ✨ Enhanced Features
- Daily log files with timestamp in filename (`msstore-repair_YYYY-MM-DD.log`)
- Timeout protection for wsreset.exe (60 seconds) to prevent hanging
- Detailed progress tracking (every 10% during app repair)
- Success/failure counters for all batch operations
- Enhanced diagnostics (service status, cache size, running processes, total app count)
- Better UI feedback with MessageBox dialogs for critical errors

### 🛡️ Improved Error Handling
- Comprehensive try-catch blocks in all functions
- Global exception handler for unhandled errors
- Better error messages with detailed exception information
- Graceful fallbacks for locked log files and missing resources
- Validation before operations (manifest existence, service availability)

### 📋 Code Quality & Standards
- Renamed all functions to PowerShell approved verb-noun convention:
  - `Invoke-CacheReset`, `Restart-StoreServices`, `Clear-StoreLocalCache`
  - `Invoke-StoreReRegistration`, `Repair-AllUWPApps`, `Invoke-Diagnostics`
  - `Invoke-FullRepair`, `Update-Progress`, `Set-BusyState`
  - `Test-AdminPrivilege`, `Request-AdminRelaunch`
- Improved parameter validation with `[Parameter(Mandatory)]`
- Script-scoped variables with explicit `$script:` prefix
- Better code organization and consistent error handling patterns

### 🔧 Technical Changes
- Thread-safe UI updates using Dispatcher with proper priorities
- Better error propagation in background worker
- Enhanced service management (added AppXSvc to monitored services)
- Improved cache management with file counting and size reporting
- Store re-registration with manifest validation and per-package error handling
- UWP app repair with manifest checks and progress logging every 10%

### 🐛 Bug Fixes
- Fixed potential race conditions in UI updates
- Fixed missing null checks for UI elements
- Fixed error handling in admin privilege check
- Fixed log directory creation with `-Force` flag
- Fixed progress bar not resetting properly
- Fixed button state management during operations

### 📝 Documentation
- Updated README.md with v2.0.0 features and troubleshooting
- Added comprehensive inline documentation
- Added detailed changelog in script header
- Improved function comments

## [1.0.0] - 2026-01-10
- Initial WPF release with Microsoft Store repair actions.
- Added diagnostics and logging.

## [1.0.1] - 2026-01-10
- Fix background worker execution and logging in pwsh previews.
- Add screenshot to README.
- Normalize screenshot filename for GitHub rendering.
