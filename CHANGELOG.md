# Changelog

## [3.0.0] - 2026-05-27

### 🎨 UI Overhaul
- Complete dark theme redesign with Windows 11 accent blue (#0078D4)
- Custom ControlTemplate for all buttons: rounded corners, hover glow, press feedback
- Three button styles: default, accent (Full Repair), danger (Cancel)
- Header bar with version badge and dynamic Admin/No-Admin indicator
- Footer status bar with animated status dot and live elapsed timer (⏱ mm:ss)

### 🌈 Color-Coded Log (RichTextBox)
- Replaced plain TextBox with RichTextBox for per-entry coloring
- Info → #DADADA (white-gray), Success → #6EC26E (green), Warning → #D9A520 (amber), Error → #F05454 (red)
- Emoji icons per level: ✔ / ⚠ / ✖ prepended to each log entry
- Entry counter shown at bottom-right of log panel
- Auto-scroll toggle checkbox to lock scrolling while reading

### ✋ Cancellation Support
- BackgroundWorker now uses WorkerSupportsCancellation = true
- Cancel button enabled during operations, disabled when idle
- `Test-CancelRequested` check at the top of each loop iteration
- Cancel propagates cleanly through Full Repair's 5-step sequence

### 💬 Confirmations & QoL
- Confirmation dialog before: Clear LocalCache, Repair All Apps, Full Repair
- Tooltip on every button explaining what the operation does
- "Clear Log View" button (clears display only, not files)
- Indeterminate progress bar until first ReportProgress call
- Progress bar resets to 0 on idle (not stuck at 100%)

### ⏱ Elapsed Time Tracking
- Operation start time recorded in `$script:OpStart`
- Live mm:ss counter updated on every ProgressChanged event
- Elapsed seconds appended to Completed/Cancelled log entries

### 🛠 Logic Improvements
- Cancel-check added to Restart-StoreServices and Repair-AllUWPApps loops
- Invoke-FullRepair checks cancel between each of the 5 steps
- Diagnostics now color-codes service status (green if Running, yellow if not)
- Cache size warning if > 100 MB

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
