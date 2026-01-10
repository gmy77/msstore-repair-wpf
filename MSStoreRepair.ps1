# ============================================================================
# Windows 11 - Microsoft Store Repair Tool (WPF)
# by Claude e Gimmy
# Version: 2.0.0 - Optimized Edition
# ============================================================================
#
# Changelog v2.0.0:
#  - Removed redundant runspace management in BackgroundWorker
#  - Improved error handling with proper try-catch blocks throughout
#  - Enhanced logging with daily log files and better error capture
#  - Renamed functions to use approved PowerShell verb-noun convention
#  - Added comprehensive diagnostics with service status and cache info
#  - Improved progress reporting with percentage and detailed messages
#  - Added timeout protection for long-running operations
#  - Better UI feedback with message boxes for errors and confirmations
#  - Optimized UWP app repair with progress tracking every 10%
#  - Added service restart counter and failure reporting
#  - Enhanced cache clearing with file counting
#  - Global exception handler for unhandled errors
#  - Code cleanup and modernization (InvokeAsync, better parameter validation)
#
# Requirements:
#  - Windows PowerShell 5.1+ or PowerShell 7+
#  - Administrator privileges
#  - Windows 10/11 with Microsoft Store
#
# ============================================================================

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Relaunch in STA mode if needed for WPF
if ([Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $exe = if (Test-Path "$PSHOME\pwsh.exe") { "$PSHOME\pwsh.exe" } else { 'powershell.exe' }
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-STA', '-File', $PSCommandPath) -WindowStyle Hidden
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Test-AdminPrivilege {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminRelaunch {
    if (Test-AdminPrivilege) {
        return $true
    }

    $result = [Windows.MessageBox]::Show(
        "This tool requires administrative privileges. Relaunch as Administrator?",
        "Microsoft Store Repair - Admin Required",
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Warning
    )

    if ($result -eq [Windows.MessageBoxResult]::Yes) {
        try {
            $exe = if (Test-Path "$PSHOME\pwsh.exe") { "$PSHOME\pwsh.exe" } else { 'powershell.exe' }
            Start-Process -FilePath $exe -ArgumentList @('-NoProfile', '-STA', '-File', $PSCommandPath) -Verb RunAs
        }
        catch {
            [Windows.MessageBox]::Show(
                "Failed to relaunch as Administrator: $($_.Exception.Message)",
                "Error",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Error
            )
        }
    }

    return $false
}

if (-not (Request-AdminRelaunch)) {
    exit
}

# Initialize logging
$script:LogDir = Join-Path $PSScriptRoot 'logs'
$script:LogFile = Join-Path $script:LogDir "msstore-repair_$(Get-Date -Format 'yyyy-MM-dd').log"

if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Microsoft Store Repair v2.0.0" Height="620" Width="980"
        WindowStartupLocation="CenterScreen" Background="#1E1E1E" Foreground="#F0F0F0">
    <Grid Margin="14">
        <Grid.RowDefinitions>
            <RowDefinition Height="*" />
            <RowDefinition Height="Auto" />
        </Grid.RowDefinitions>
        <Grid Grid.Row="0">
            <Grid.ColumnDefinitions>
                <ColumnDefinition Width="240" />
                <ColumnDefinition Width="*" />
            </Grid.ColumnDefinitions>
            <Border Grid.Column="0" Background="#2A2A2A" CornerRadius="8" Padding="12" Margin="0,0,12,0">
                <StackPanel>
                    <TextBlock Text="Microsoft Store Repair" FontSize="16" FontWeight="Bold" Margin="0,0,0,10" />
                    <Button Name="BtnResetCache" Content="Reset Cache (wsreset)" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnRestartServices" Content="Restart Services" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnClearCache" Content="Clear LocalCache" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnReRegister" Content="Re-register Store" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnRepairApps" Content="Repair All Apps" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnFullRepair" Content="Full Repair" Margin="0,0,0,8" Height="34" />
                    <Button Name="BtnDiagnostics" Content="Diagnostics" Margin="0,0,0,8" Height="34" />
                    <Separator Margin="0,6,0,6" />
                    <Button Name="BtnOpenLog" Content="Open Log Folder" Height="34" />
                </StackPanel>
            </Border>
            <Border Grid.Column="1" Background="#141414" CornerRadius="8" Padding="12">
                <Grid>
                    <Grid.RowDefinitions>
                        <RowDefinition Height="Auto" />
                        <RowDefinition Height="*" />
                    </Grid.RowDefinitions>
                    <TextBlock Text="Log" FontSize="14" FontWeight="Bold" Margin="0,0,0,8" />
                    <TextBox Name="LogBox" Grid.Row="1" IsReadOnly="True" TextWrapping="Wrap" VerticalScrollBarVisibility="Auto"
                             Background="#0F0F0F" BorderBrush="#2E2E2E" Foreground="#DADADA" FontFamily="Consolas" FontSize="12" />
                </Grid>
            </Border>
        </Grid>
        <Border Grid.Row="1" Background="#2A2A2A" CornerRadius="8" Padding="10" Margin="0,12,0,0">
            <DockPanel>
                <TextBlock Name="StatusText" Text="Idle" DockPanel.Dock="Left" />
                <ProgressBar Name="ProgressBar" DockPanel.Dock="Right" Width="260" Height="18" Margin="12,0,0,0" />
            </DockPanel>
        </Border>
    </Grid>
</Window>
'@

$reader = (New-Object System.Xml.XmlNodeReader $xaml)
$window = [Windows.Markup.XamlReader]::Load($reader)

# Get UI element references
$LogBox = $window.FindName('LogBox')
$StatusText = $window.FindName('StatusText')
$ProgressBar = $window.FindName('ProgressBar')

$script:Buttons = @(
    $window.FindName('BtnResetCache')
    $window.FindName('BtnRestartServices')
    $window.FindName('BtnClearCache')
    $window.FindName('BtnReRegister')
    $window.FindName('BtnRepairApps')
    $window.FindName('BtnFullRepair')
    $window.FindName('BtnDiagnostics')
    $window.FindName('BtnOpenLog')
)

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info', 'Success', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $line = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
    }
    catch {
        # Fallback if log file is locked
    }

    if ($window -and $LogBox) {
        $window.Dispatcher.Invoke([action] {
            $LogBox.AppendText("$line`n")
            $LogBox.ScrollToEnd()
        }, [Windows.Threading.DispatcherPriority]::Background)
    }
}

function Test-AppxSupport {
    if (-not (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) -or
        -not (Get-Command Add-AppxPackage -ErrorAction SilentlyContinue)) {
        Write-Log 'Appx cmdlets not available. Use Windows PowerShell 5.1 or import WindowsCompatibility module.' 'Warning'
        return $false
    }
    return $true
}

# Global exception handler
$null = [AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    $message = $eventArgs.ExceptionObject.ToString()
    $logEntry = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [Fatal] Unhandled: $message"
    Add-Content -Path $script:LogFile -Value $logEntry -ErrorAction SilentlyContinue
})

function Set-BusyState {
    param(
        [bool]$IsBusy,
        [string]$Status = 'Idle'
    )

    $window.Dispatcher.Invoke([action] {
        foreach ($btn in $script:Buttons) {
            $btn.IsEnabled = -not $IsBusy
        }
        $StatusText.Text = $Status
        $ProgressBar.Value = if ($IsBusy) { 0 } else { 100 }
        $ProgressBar.IsIndeterminate = $false
    }, [Windows.Threading.DispatcherPriority]::Normal)
}

$script:ActiveWorker = $null

function Update-Progress {
    param(
        [int]$Percent,
        [string]$Message
    )

    if ($script:ActiveWorker) {
        $script:ActiveWorker.ReportProgress($Percent, $Message)
    }
}

function Start-Action {
    param(
        [Parameter(Mandatory)]
        [string]$Title,

        [Parameter(Mandatory)]
        [scriptblock]$Action
    )

    if ($script:ActiveWorker -and $script:ActiveWorker.IsBusy) {
        Write-Log 'Another operation is already in progress.' 'Warning'
        [Windows.MessageBox]::Show(
            'Please wait for the current operation to complete.',
            'Operation In Progress',
            [Windows.MessageBoxButton]::OK,
            [Windows.MessageBoxImage]::Information
        )
        return
    }

    Set-BusyState -IsBusy $true -Status $Title
    Write-Log "Starting: $Title" 'Info'

    $worker = New-Object ComponentModel.BackgroundWorker
    $worker.WorkerReportsProgress = $true

    $worker.add_DoWork({
        param($sender, $e)
        try {
            & $Action
            $e.Result = $true
        }
        catch {
            $e.Result = $_
            throw
        }
    })

    $worker.add_ProgressChanged({
        param($sender, $e)
        $window.Dispatcher.InvokeAsync([action] {
            if ($e.ProgressPercentage -ge 0 -and $e.ProgressPercentage -le 100) {
                $ProgressBar.Value = $e.ProgressPercentage
            }
            if ($e.UserState) {
                $StatusText.Text = $e.UserState.ToString()
            }
        })
    })

    $worker.add_RunWorkerCompleted({
        param($sender, $e)

        if ($e.Error) {
            $errorMsg = $e.Error.Message
            Write-Log "Failed: $Title - $errorMsg" 'Error'
            [Windows.MessageBox]::Show(
                "Operation failed: $errorMsg",
                "Error - $Title",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Error
            )
        }
        elseif ($e.Result -is [Exception]) {
            $errorMsg = $e.Result.Message
            Write-Log "Failed: $Title - $errorMsg" 'Error'
        }
        else {
            Write-Log "Completed: $Title" 'Success'
        }

        Set-BusyState -IsBusy $false -Status 'Ready'
        $script:ActiveWorker = $null
    })

    $script:ActiveWorker = $worker
    $worker.RunWorkerAsync()
}

function Invoke-CacheReset {
    Write-Log 'Launching Windows Store Cache Reset (wsreset.exe)...' 'Info'
    try {
        $process = Start-Process 'wsreset.exe' -PassThru -WindowStyle Minimized
        $timeout = 60
        if (-not $process.WaitForExit($timeout * 1000)) {
            Write-Log "wsreset.exe exceeded timeout of $timeout seconds" 'Warning'
            $process.Kill()
        }
        else {
            Write-Log 'Cache reset completed' 'Success'
        }
    }
    catch {
        Write-Log "Failed to run wsreset.exe: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Restart-StoreServices {
    $services = @(
        @{ Name = 'wuauserv'; Display = 'Windows Update' }
        @{ Name = 'bits'; Display = 'Background Intelligent Transfer Service' }
        @{ Name = 'WSService'; Display = 'Windows Store Service' }
        @{ Name = 'InstallService'; Display = 'Microsoft Store Install Service' }
        @{ Name = 'AppXSvc'; Display = 'AppX Deployment Service' }
    )

    $restartedCount = 0
    $failedCount = 0

    foreach ($svc in $services) {
        try {
            $service = Get-Service -Name $svc.Name -ErrorAction Stop

            Write-Log "Restarting $($svc.Display) ($($service.Status))..." 'Info'

            if ($service.Status -eq 'Running') {
                Stop-Service -Name $svc.Name -Force -ErrorAction Stop -WarningAction SilentlyContinue
                Start-Sleep -Milliseconds 300
            }

            Start-Service -Name $svc.Name -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log "$($svc.Display) restarted successfully" 'Success'
            $restartedCount++
        }
        catch {
            Write-Log "$($svc.Display): $_" 'Warning'
            $failedCount++
        }
    }

    Write-Log "Services restarted: $restartedCount, Failed: $failedCount" 'Info'
}

function Clear-StoreLocalCache {
    $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"

    Write-Log 'Terminating Microsoft Store processes...' 'Info'
    $storeProcesses = Get-Process -Name '*WinStore*', 'WinStore.App' -ErrorAction SilentlyContinue
    if ($storeProcesses) {
        $storeProcesses | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Write-Log "Stopped $($storeProcesses.Count) Store process(es)" 'Info'
    }

    if (-not (Test-Path $cachePath)) {
        Write-Log "Cache folder not found: $cachePath" 'Warning'
        return
    }

    try {
        $items = Get-ChildItem -Path $cachePath -Recurse -Force -ErrorAction Stop
        $itemCount = $items.Count

        Write-Log "Clearing $itemCount cache item(s) from: $cachePath" 'Info'
        Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction Stop
        Write-Log 'Local cache cleared successfully' 'Success'
    }
    catch {
        Write-Log "Failed to clear cache: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Invoke-StoreReRegistration {
    if (-not (Test-AppxSupport)) {
        Write-Log 'Skipping Store re-registration: Appx cmdlets unavailable' 'Warning'
        return
    }

    Write-Log 'Re-registering Microsoft Store packages...' 'Info'
    try {
        $storePackages = Get-AppxPackage -Name '*WindowsStore*' -AllUsers -ErrorAction Stop

        if (-not $storePackages) {
            Write-Log 'No Microsoft Store packages found' 'Warning'
            return
        }

        $registeredCount = 0
        foreach ($pkg in $storePackages) {
            $manifestPath = Join-Path $pkg.InstallLocation 'AppXManifest.xml'

            if (Test-Path $manifestPath) {
                try {
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
                    Write-Log "Re-registered: $($pkg.Name) v$($pkg.Version)" 'Success'
                    $registeredCount++
                }
                catch {
                    Write-Log "Failed to re-register $($pkg.Name): $_" 'Warning'
                }
            }
        }

        Write-Log "Re-registered $registeredCount Store package(s)" 'Info'
    }
    catch {
        Write-Log "Store re-registration failed: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Repair-AllUWPApps {
    if (-not (Test-AppxSupport)) {
        Write-Log 'Skipping app repair: Appx cmdlets unavailable' 'Warning'
        return
    }

    Write-Log 'Starting re-registration of all UWP apps...' 'Info'

    try {
        $apps = @(Get-AppxPackage -AllUsers -ErrorAction Stop)
    }
    catch {
        Write-Log "Failed to enumerate apps: $($_.Exception.Message)" 'Error'
        throw
    }

    $total = $apps.Count
    if ($total -eq 0) {
        Write-Log 'No UWP apps found to repair' 'Warning'
        return
    }

    Write-Log "Found $total UWP app(s) to re-register" 'Info'

    $successCount = 0
    $failureCount = 0

    for ($i = 0; $i -lt $total; $i++) {
        $app = $apps[$i]
        $percent = [math]::Round((($i + 1) / $total) * 100)
        Update-Progress -Percent $percent -Message "Processing: $($app.Name)"

        $manifestPath = Join-Path $app.InstallLocation 'AppXManifest.xml'

        if (-not (Test-Path $manifestPath)) {
            Write-Log "Manifest not found for $($app.Name)" 'Warning'
            $failureCount++
            continue
        }

        try {
            Add-AppxPackage -DisableDevelopmentMode -Register $manifestPath -ErrorAction Stop
            $successCount++
        }
        catch {
            $failureCount++
        }

        # Log progress every 10%
        if ($percent % 10 -eq 0) {
            Write-Log "Progress: $percent% ($successCount success, $failureCount failed)" 'Info'
        }
    }

    Write-Log "Completed: $successCount succeeded, $failureCount failed out of $total apps" $(if ($failureCount -eq 0) { 'Success' } else { 'Warning' })
}

function Invoke-Diagnostics {
    Write-Log '=== System Diagnostics Started ===' 'Info'

    try {
        # Check services
        Write-Log '--- Service Status ---' 'Info'
        $services = @(
            @{ Name = 'wuauserv'; Display = 'Windows Update' }
            @{ Name = 'bits'; Display = 'BITS' }
            @{ Name = 'WSService'; Display = 'Windows Store Service' }
            @{ Name = 'InstallService'; Display = 'Store Install Service' }
            @{ Name = 'AppXSvc'; Display = 'AppX Deployment Service' }
        )

        foreach ($svc in $services) {
            $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
            if ($service) {
                $status = $service.Status
                $startType = $service.StartType
                Write-Log "$($svc.Display): $status (StartType: $startType)" 'Info'
            }
            else {
                Write-Log "$($svc.Display): Not Found" 'Warning'
            }
        }

        # Check Microsoft Store package
        Write-Log '--- Microsoft Store Package ---' 'Info'
        if (Test-AppxSupport) {
            $store = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue
            if ($store) {
                Write-Log "Name: $($store.Name)" 'Info'
                Write-Log "Version: $($store.Version)" 'Info'
                Write-Log "Architecture: $($store.Architecture)" 'Info'
                Write-Log "Install Location: $($store.InstallLocation)" 'Info'
            }
            else {
                Write-Log 'Microsoft Store package NOT FOUND' 'Error'
            }

            # Count total UWP apps
            $appCount = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue).Count
            Write-Log "Total UWP apps installed: $appCount" 'Info'
        }

        # Check cache
        Write-Log '--- Cache Information ---' 'Info'
        $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
        if (Test-Path $cachePath) {
            $cacheItems = Get-ChildItem -Path $cachePath -Recurse -File -ErrorAction SilentlyContinue
            $totalSize = ($cacheItems | Measure-Object -Property Length -Sum).Sum
            $sizeMB = [math]::Round($totalSize / 1MB, 2)
            $fileCount = $cacheItems.Count
            Write-Log "Cache location: $cachePath" 'Info'
            Write-Log "Cache size: $sizeMB MB ($fileCount files)" 'Info'
        }
        else {
            Write-Log "Cache folder not found: $cachePath" 'Warning'
        }

        # Check Store processes
        Write-Log '--- Running Processes ---' 'Info'
        $storeProcs = Get-Process -Name '*WinStore*', 'WinStore.App' -ErrorAction SilentlyContinue
        if ($storeProcs) {
            foreach ($proc in $storeProcs) {
                Write-Log "Process: $($proc.Name) (PID: $($proc.Id))" 'Info'
            }
        }
        else {
            Write-Log 'No Microsoft Store processes running' 'Info'
        }

        Write-Log '=== Diagnostics Completed ===' 'Success'
    }
    catch {
        Write-Log "Diagnostics error: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Invoke-FullRepair {
    Write-Log 'Starting Full Repair sequence...' 'Info'

    Update-Progress -Percent 10 -Message 'Step 1/5: Resetting cache'
    Invoke-CacheReset

    Update-Progress -Percent 30 -Message 'Step 2/5: Restarting services'
    Restart-StoreServices

    Update-Progress -Percent 50 -Message 'Step 3/5: Clearing local cache'
    Clear-StoreLocalCache

    Update-Progress -Percent 70 -Message 'Step 4/5: Re-registering Store'
    Invoke-StoreReRegistration

    Update-Progress -Percent 85 -Message 'Step 5/5: Repairing all apps'
    Repair-AllUWPApps

    Update-Progress -Percent 100 -Message 'Full repair completed'
    Write-Log 'Full Repair sequence completed successfully' 'Success'
}

# Wire up button event handlers
$window.FindName('BtnResetCache').Add_Click({
    Start-Action -Title 'Reset Cache' -Action { Invoke-CacheReset }
})

$window.FindName('BtnRestartServices').Add_Click({
    Start-Action -Title 'Restart Services' -Action { Restart-StoreServices }
})

$window.FindName('BtnClearCache').Add_Click({
    Start-Action -Title 'Clear LocalCache' -Action { Clear-StoreLocalCache }
})

$window.FindName('BtnReRegister').Add_Click({
    Start-Action -Title 'Re-register Store' -Action { Invoke-StoreReRegistration }
})

$window.FindName('BtnRepairApps').Add_Click({
    Start-Action -Title 'Repair All Apps' -Action { Repair-AllUWPApps }
})

$window.FindName('BtnFullRepair').Add_Click({
    Start-Action -Title 'Full Repair' -Action { Invoke-FullRepair }
})

$window.FindName('BtnDiagnostics').Add_Click({
    Start-Action -Title 'Diagnostics' -Action { Invoke-Diagnostics }
})

$window.FindName('BtnOpenLog').Add_Click({
    try {
        Start-Process 'explorer.exe' -ArgumentList $script:LogDir
    }
    catch {
        Write-Log "Failed to open log folder: $_" 'Error'
    }
})

Write-Log 'Ready.' 'Info'
$window.ShowDialog() | Out-Null
