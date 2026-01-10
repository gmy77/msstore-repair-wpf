# Windows 11 - Microsoft Store Repair Tool (WPF)
# by Claude e Gimmy

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Relaunch in STA if needed for WPF.
if ([System.Threading.Thread]::CurrentThread.ApartmentState -ne 'STA') {
    $exe = if (Test-Path "$PSHOME\pwsh.exe") { "$PSHOME\pwsh.exe" } else { 'powershell.exe' }
    Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-STA','-File',"$PSCommandPath")
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

function Ensure-Admin {
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole]::Administrator
    )

    if ($isAdmin) {
        return $true
    }

    $message = "This tool requires administrative privileges. Relaunch as Administrator?"
    $caption = "Microsoft Store Repair"
    $result = [System.Windows.MessageBox]::Show($message, $caption, 'YesNo', 'Warning')
    if ($result -eq 'Yes') {
        $exe = if (Test-Path "$PSHOME\pwsh.exe") { "$PSHOME\pwsh.exe" } else { 'powershell.exe' }
        Start-Process -FilePath $exe -ArgumentList @('-NoProfile','-STA','-File',"$PSCommandPath") -Verb RunAs
    }

    return $false
}

if (-not (Ensure-Admin)) {
    exit
}

$logDir = Join-Path $PSScriptRoot 'logs'
$logFile = Join-Path $logDir 'msstore-repair.log'
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir | Out-Null
}

[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Microsoft Store Repair v1.0.0" Height="620" Width="980"
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

$LogBox = $window.FindName('LogBox')
$StatusText = $window.FindName('StatusText')
$ProgressBar = $window.FindName('ProgressBar')

$buttons = @(
    $window.FindName('BtnResetCache'),
    $window.FindName('BtnRestartServices'),
    $window.FindName('BtnClearCache'),
    $window.FindName('BtnReRegister'),
    $window.FindName('BtnRepairApps'),
    $window.FindName('BtnFullRepair'),
    $window.FindName('BtnDiagnostics'),
    $window.FindName('BtnOpenLog')
)

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info','Success','Warning','Error')] [string]$Level = 'Info'
    )

    $timestamp = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$timestamp] [$Level] $Message"

    Add-Content -Path $logFile -Value $line
    $window.Dispatcher.Invoke([action]{
        $LogBox.AppendText($line + [Environment]::NewLine)
        $LogBox.ScrollToEnd()
    })
}

function Set-Busy {
    param([bool]$IsBusy, [string]$Status = 'Idle')

    $window.Dispatcher.Invoke([action]{
        foreach ($btn in $buttons) {
            $btn.IsEnabled = -not $IsBusy
        }
        $StatusText.Text = $Status
        if (-not $IsBusy) {
            $ProgressBar.Value = 0
        }
    })
}

$script:ActiveWorker = $null
function Report-Progress {
    param([int]$Percent, [string]$Message)

    if ($script:ActiveWorker) {
        $script:ActiveWorker.ReportProgress($Percent, $Message)
    }
}

function Start-Action {
    param(
        [string]$Title,
        [scriptblock]$Action
    )

    if ($script:ActiveWorker -and $script:ActiveWorker.IsBusy) {
        Write-Log 'An operation is already running.' 'Warning'
        return
    }

    Set-Busy -IsBusy $true -Status $Title
    Write-Log "Starting: $Title" 'Info'

    $worker = New-Object System.ComponentModel.BackgroundWorker
    $worker.WorkerReportsProgress = $true

    $worker.DoWork = {
        & $using:Action
    }

    $worker.ProgressChanged = {
        param($sender, $e)
        $window.Dispatcher.Invoke([action]{
            if ($e.ProgressPercentage -ge 0) {
                $ProgressBar.Value = $e.ProgressPercentage
            }
            if ($e.UserState) {
                $StatusText.Text = $e.UserState
            }
        })
    }

    $worker.RunWorkerCompleted = {
        param($sender, $e)
        if ($e.Error) {
            Write-Log "Failed: $Title - $($e.Error.Exception.Message)" 'Error'
        }
        else {
            Write-Log "Completed: $Title" 'Success'
        }
        Set-Busy -IsBusy $false -Status 'Idle'
        $script:ActiveWorker = $null
    }

    $script:ActiveWorker = $worker
    $worker.RunWorkerAsync()
}

function Reset-Cache {
    Write-Log 'Launching wsreset.exe...' 'Info'
    Start-Process 'wsreset.exe' -Wait
}

function Restart-Services {
    $services = @(
        @{Name='wuauserv'; Display='Windows Update'},
        @{Name='bits'; Display='Background Intelligent Transfer'},
        @{Name='WSService'; Display='Windows Store Service'},
        @{Name='InstallService'; Display='Microsoft Store Install Service'}
    )

    foreach ($svc in $services) {
        $name = $svc.Name
        $display = $svc.Display
        try {
            $service = Get-Service -Name $name -ErrorAction Stop
            Write-Log "Stopping $display" 'Info'
            Stop-Service -Name $name -Force -ErrorAction Stop
            Start-Sleep -Milliseconds 500
            Write-Log "Starting $display" 'Info'
            Start-Service -Name $name -ErrorAction Stop
            Write-Log "$display restarted" 'Success'
        }
        catch {
            Write-Log "$display not available or failed to restart" 'Warning'
        }
    }
}

function Clear-LocalCache {
    $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"

    Write-Log 'Closing Microsoft Store process...' 'Info'
    Get-Process *WinStore* -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 1

    if (Test-Path $cachePath) {
        Write-Log "Removing cache: $cachePath" 'Info'
        Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction SilentlyContinue
        Write-Log 'Local cache deleted.' 'Success'
    }
    else {
        Write-Log 'Cache folder not found.' 'Warning'
    }
}

function ReRegister-Store {
    Write-Log 'Re-registering Microsoft Store...' 'Info'
    Get-AppxPackage *WindowsStore* -AllUsers | ForEach-Object {
        Add-AppxPackage -DisableDevelopmentMode -Register "$($_.InstallLocation)\AppXManifest.xml" -ErrorAction SilentlyContinue
    }
}

function Repair-AllApps {
    Write-Log 'Re-registering all UWP apps...' 'Info'
    $apps = Get-AppxPackage -AllUsers
    $total = if ($apps) { $apps.Count } else { 0 }
    $index = 0
    $failures = 0

    foreach ($app in $apps) {
        $index++
        $percent = if ($total -gt 0) { [math]::Round(($index / $total) * 100) } else { 0 }
        Report-Progress -Percent $percent -Message "Re-registering $($app.Name)"

        try {
            Add-AppxPackage -DisableDevelopmentMode -Register "$($app.InstallLocation)\AppXManifest.xml" -ErrorAction Stop
        }
        catch {
            $failures++
        }
    }

    if ($failures -gt 0) {
        Write-Log "Completed with $failures package errors." 'Warning'
    }
}

function Run-Diagnostics {
    Write-Log 'Diagnostics started.' 'Info'

    $services = @(
        @{Name='wuauserv'; Display='Windows Update'},
        @{Name='bits'; Display='BITS'},
        @{Name='WSService'; Display='Windows Store Service'},
        @{Name='InstallService'; Display='Store Install Service'},
        @{Name='AppXSvc'; Display='AppX Deployment Service'}
    )

    foreach ($svc in $services) {
        $service = Get-Service -Name $svc.Name -ErrorAction SilentlyContinue
        if ($service) {
            Write-Log "$($svc.Display): $($service.Status)" 'Info'
        }
        else {
            Write-Log "$($svc.Display): Not found" 'Warning'
        }
    }

    $store = Get-AppxPackage -Name Microsoft.WindowsStore -ErrorAction SilentlyContinue
    if ($store) {
        Write-Log "Store version: $($store.Version)" 'Info'
        Write-Log "Store architecture: $($store.Architecture)" 'Info'
    }
    else {
        Write-Log 'Microsoft Store not found.' 'Error'
    }

    $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
    if (Test-Path $cachePath) {
        $size = (Get-ChildItem -Path $cachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        Write-Log "Cache size: $sizeMB MB" 'Info'
    }
}

function Full-Repair {
    Report-Progress -Percent 5 -Message 'Resetting cache'
    Reset-Cache
    Report-Progress -Percent 25 -Message 'Restarting services'
    Restart-Services
    Report-Progress -Percent 50 -Message 'Clearing LocalCache'
    Clear-LocalCache
    Report-Progress -Percent 75 -Message 'Re-registering Store'
    ReRegister-Store
    Report-Progress -Percent 95 -Message 'Repairing all apps'
    Repair-AllApps
    Report-Progress -Percent 100 -Message 'Complete'
}

$window.FindName('BtnResetCache').Add_Click({ Start-Action -Title 'Reset Cache' -Action { Reset-Cache } })
$window.FindName('BtnRestartServices').Add_Click({ Start-Action -Title 'Restart Services' -Action { Restart-Services } })
$window.FindName('BtnClearCache').Add_Click({ Start-Action -Title 'Clear LocalCache' -Action { Clear-LocalCache } })
$window.FindName('BtnReRegister').Add_Click({ Start-Action -Title 'Re-register Store' -Action { ReRegister-Store } })
$window.FindName('BtnRepairApps').Add_Click({ Start-Action -Title 'Repair All Apps' -Action { Repair-AllApps } })
$window.FindName('BtnFullRepair').Add_Click({ Start-Action -Title 'Full Repair' -Action { Full-Repair } })
$window.FindName('BtnDiagnostics').Add_Click({ Start-Action -Title 'Diagnostics' -Action { Run-Diagnostics } })
$window.FindName('BtnOpenLog').Add_Click({ Start-Process -FilePath 'explorer.exe' -ArgumentList @($logDir) })

Write-Log 'Ready.' 'Info'
$window.ShowDialog() | Out-Null
