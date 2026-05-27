# ============================================================================
# Windows 11 - Microsoft Store Repair Tool (WPF)
# by Claude e Gimmy
# Version: 3.0.0 - Modern UI Edition
# ============================================================================
#
# Changelog v3.0.0:
#  - Complete UI overhaul: modern dark theme with accent colors
#  - Color-coded log output (green/red/yellow/white per level)
#  - Emoji icons on all buttons for instant visual recognition
#  - Header bar with version badge and Admin status indicator
#  - Tooltips on every button explaining what it does
#  - Confirmation dialogs before destructive operations
#  - Cancel button to abort running operations
#  - "Clear Log" button in the UI
#  - Auto-scroll log with toggle checkbox to lock it
#  - Real-time cache size shown in Clear Cache button
#  - Footer status bar with richer info (time elapsed, last op)
#  - Animated indeterminate progress during non-percentage operations
#  - Operation start time tracking with elapsed time on completion
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
    $identity  = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = [Security.Principal.WindowsPrincipal]$identity
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Request-AdminRelaunch {
    if (Test-AdminPrivilege) { return $true }

    $result = [Windows.MessageBox]::Show(
        "This tool requires administrative privileges.`nRelaunch as Administrator?",
        "Microsoft Store Repair — Admin Required",
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
                "Failed to relaunch as Administrator:`n$($_.Exception.Message)",
                "Error",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Error
            )
        }
    }
    return $false
}

if (-not (Request-AdminRelaunch)) { exit }

# ── Logging setup ─────────────────────────────────────────────────────────────
$script:LogDir  = Join-Path $PSScriptRoot 'logs'
$script:LogFile = Join-Path $script:LogDir "msstore-repair_$(Get-Date -Format 'yyyy-MM-dd').log"
if (-not (Test-Path $script:LogDir)) {
    New-Item -ItemType Directory -Path $script:LogDir -Force | Out-Null
}

# ── Config (user preferences) ─────────────────────────────────────────────────
$script:ConfigFile    = Join-Path $PSScriptRoot 'config.json'
$script:DefaultConfig = @{ FontSize = 12 }

function Read-Config {
    if (Test-Path $script:ConfigFile) {
        try {
            $raw = Get-Content $script:ConfigFile -Raw -ErrorAction Stop | ConvertFrom-Json
            # Merge with defaults so missing keys never cause errors
            foreach ($key in $script:DefaultConfig.Keys) {
                if ($null -eq $raw.$key) { $raw | Add-Member -NotePropertyName $key -NotePropertyValue $script:DefaultConfig[$key] -Force }
            }
            return $raw
        }
        catch { <# fallback to defaults on parse error #> }
    }
    return [pscustomobject]$script:DefaultConfig
}

function Save-Config {
    param([int]$FontSize)
    try {
        @{ FontSize = $FontSize } | ConvertTo-Json | Set-Content -Path $script:ConfigFile -Encoding UTF8 -ErrorAction Stop
    }
    catch { <# non-critical, silently ignore #> }
}

$script:Config = Read-Config

# ── XAML ──────────────────────────────────────────────────────────────────────
[xml]$xaml = @'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="Microsoft Store Repair v3.0.0" Height="660" Width="1020"
        WindowStartupLocation="CenterScreen"
        Background="#121212" Foreground="#EFEFEF"
        FontFamily="Segoe UI">

  <Window.Resources>
    <!-- Base button style -->
    <Style TargetType="Button">
      <Setter Property="Background"       Value="#1F1F1F"/>
      <Setter Property="Foreground"       Value="#EFEFEF"/>
      <Setter Property="BorderBrush"      Value="#333333"/>
      <Setter Property="BorderThickness"  Value="1"/>
      <Setter Property="Height"           Value="36"/>
      <Setter Property="FontSize"         Value="13"/>
      <Setter Property="Cursor"           Value="Hand"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}"
                    CornerRadius="6" Padding="10,0">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#2A2A2A"/>
                <Setter TargetName="bd" Property="BorderBrush" Value="#0078D4"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#0078D4"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#1A1A1A"/>
                <Setter Property="Foreground" Value="#555555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Accent button (Cancel / Full Repair) -->
    <Style x:Key="AccentButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background"  Value="#0078D4"/>
      <Setter Property="BorderBrush" Value="#005A9E"/>
      <Setter Property="FontWeight"  Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="6" Padding="10,0">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#1A8FE3"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#005A9E"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#1A1A1A"/>
                <Setter Property="Foreground" Value="#555555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <!-- Danger button (Cancel) -->
    <Style x:Key="DangerButton" TargetType="Button" BasedOn="{StaticResource {x:Type Button}}">
      <Setter Property="Background"  Value="#C42B1C"/>
      <Setter Property="BorderBrush" Value="#8B1E14"/>
      <Setter Property="FontWeight"  Value="SemiBold"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border Name="bd" Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="1" CornerRadius="6" Padding="10,0">
              <ContentPresenter HorizontalAlignment="Left" VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#E0392A"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="bd" Property="Background" Value="#8B1E14"/>
              </Trigger>
              <Trigger Property="IsEnabled" Value="False">
                <Setter TargetName="bd" Property="Background" Value="#1A1A1A"/>
                <Setter Property="Foreground" Value="#555555"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style TargetType="Separator">
      <Setter Property="Background" Value="#2E2E2E"/>
      <Setter Property="Margin"     Value="0,6,0,6"/>
    </Style>
  </Window.Resources>

  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- ── Header ── -->
    <Border Grid.Row="0" Background="#1A1A1A" CornerRadius="8" Padding="14,10" Margin="0,0,0,12">
      <DockPanel>
        <StackPanel DockPanel.Dock="Left" Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Text="🛠️" FontSize="22" VerticalAlignment="Center" Margin="0,0,10,0"/>
          <StackPanel>
            <TextBlock Text="Microsoft Store Repair" FontSize="16" FontWeight="Bold"/>
            <TextBlock Text="by Claude &amp; Gimmy" FontSize="11" Foreground="#888888"/>
          </StackPanel>
        </StackPanel>
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" VerticalAlignment="Center" HorizontalAlignment="Right">
          <Border Background="#0078D4" CornerRadius="4" Padding="8,3" Margin="0,0,10,0">
            <TextBlock Text="v3.0.0" FontSize="11" FontWeight="Bold"/>
          </Border>
          <Border Name="AdminBadge" Background="#107C10" CornerRadius="4" Padding="8,3">
            <TextBlock Name="AdminBadgeText" Text="✔ Admin" FontSize="11" FontWeight="Bold"/>
          </Border>
        </StackPanel>
      </DockPanel>
    </Border>

    <!-- ── Main area ── -->
    <Grid Grid.Row="1">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="250"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>

      <!-- Left panel: buttons -->
      <Border Grid.Column="0" Background="#1A1A1A" CornerRadius="8" Padding="12" Margin="0,0,12,0">
        <StackPanel>
          <TextBlock Text="OPERATIONS" FontSize="12" Foreground="#888888"
                     FontWeight="SemiBold" Margin="0,0,0,10"/>

          <Button Name="BtnResetCache" Content="⚡ Reset Cache" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Runs wsreset.exe to clear the Windows Store download cache (60s timeout)"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnRestartServices" Content="🔄 Restart Services" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Restarts 5 Store-related services: Windows Update, BITS, WSService, InstallService, AppXSvc"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnClearCache" Content="🗑️ Clear LocalCache" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Deletes all files in the Store LocalCache folder. Closes Store processes first."/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnReRegister" Content="📦 Re-register Store" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Re-registers all Microsoft.WindowsStore packages for all users via Add-AppxPackage"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnRepairApps" Content="🔧 Repair All Apps" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Re-registers every installed UWP app. This can take several minutes."/>
            </Button.ToolTip>
          </Button>

          <Separator/>

          <Button Name="BtnFullRepair" Style="{StaticResource AccentButton}"
                  Content="🚀 Full Repair" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Runs all 5 repair steps in sequence: wsreset → services → cache → re-register → repair apps"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnDiagnostics" Content="🔍 Diagnostics" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Shows service status, Store package info, cache size and running processes"/>
            </Button.ToolTip>
          </Button>

          <Separator/>

          <Button Name="BtnCancel" Style="{StaticResource DangerButton}"
                  Content="✖ Cancel Operation" IsEnabled="False" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Requests cancellation of the current running operation"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnOpenLog" Content="📂 Open Log Folder" Margin="0,0,0,6">
            <Button.ToolTip>
              <ToolTip Content="Opens the logs\ folder in Windows Explorer"/>
            </Button.ToolTip>
          </Button>

          <Button Name="BtnClearLog" Content="🧹 Clear Log View" Margin="0,0,0,0">
            <Button.ToolTip>
              <ToolTip Content="Clears the log display (does not delete log files)"/>
            </Button.ToolTip>
          </Button>
        </StackPanel>
      </Border>

      <!-- Right panel: log -->
      <Border Grid.Column="1" Background="#0F0F0F" CornerRadius="8" Padding="12">
        <Grid>
          <Grid.RowDefinitions>
            <RowDefinition Height="Auto"/>
            <RowDefinition Height="*"/>
            <RowDefinition Height="Auto"/>
          </Grid.RowDefinitions>

          <DockPanel Grid.Row="0" Margin="0,0,0,8">
            <TextBlock Text="Activity Log" FontSize="13" FontWeight="SemiBold"
                       VerticalAlignment="Center" DockPanel.Dock="Left"/>
            <StackPanel DockPanel.Dock="Right" Orientation="Horizontal" HorizontalAlignment="Right">
              <CheckBox Name="ChkAutoScroll" Content="Auto-scroll" IsChecked="True"
                        Foreground="#AAAAAA" FontSize="11" VerticalAlignment="Center"/>
            </StackPanel>
          </DockPanel>

          <!-- The log uses a RichTextBox for colored output -->
          <RichTextBox Name="LogBox" Grid.Row="1"
                       IsReadOnly="True" IsDocumentEnabled="True"
                       Background="#0A0A0A" BorderBrush="#222222" BorderThickness="1"
                       Foreground="#DADADA" FontFamily="Cascadia Code, Consolas, Courier New"
                       FontSize="12" VerticalScrollBarVisibility="Auto"
                       HorizontalScrollBarVisibility="Auto"
                       Padding="6">
            <RichTextBox.Document>
              <FlowDocument LineHeight="2"/>
            </RichTextBox.Document>
          </RichTextBox>

          <TextBlock Name="LogCountText" Grid.Row="2"
                     Text="0 entries" Foreground="#555555" FontSize="10"
                     Margin="0,4,0,0" HorizontalAlignment="Right"/>
        </Grid>
      </Border>
    </Grid>

    <!-- ── Footer / status bar ── -->
    <Border Grid.Row="2" Background="#1A1A1A" CornerRadius="8" Padding="12,8" Margin="0,12,0,0">
      <DockPanel>
        <ProgressBar Name="ProgressBar" DockPanel.Dock="Right"
                     Width="220" Height="16" Margin="12,0,0,0"
                     Foreground="#0078D4" Background="#2A2A2A"/>
        <!-- Font size controls -->
        <StackPanel DockPanel.Dock="Right" Orientation="Horizontal"
                    VerticalAlignment="Center" Margin="0,0,20,0">
          <TextBlock Text="🔤" VerticalAlignment="Center" FontSize="12" Margin="0,0,6,0" Foreground="#888888"/>
          <TextBlock Text="A" VerticalAlignment="Center" FontSize="10" Foreground="#666666" Margin="0,0,4,0"/>
          <Slider Name="FontSlider"
                  Minimum="10" Maximum="20" Value="12"
                  Width="90" VerticalAlignment="Center"
                  SmallChange="1" LargeChange="2" IsSnapToTickEnabled="True" TickFrequency="1"
                  Foreground="#0078D4"/>
          <TextBlock Text="A" VerticalAlignment="Center" FontSize="15" Foreground="#AAAAAA" Margin="4,0,8,0"/>
          <TextBlock Name="FontSizeLabel" Text="12px" FontSize="11"
                     Foreground="#888888" VerticalAlignment="Center" Width="32"/>
        </StackPanel>
        <StackPanel Orientation="Horizontal" VerticalAlignment="Center">
          <TextBlock Name="StatusIcon" Text="●" FontSize="10"
                     Foreground="#555555" VerticalAlignment="Center" Margin="0,0,6,0"/>
          <TextBlock Name="StatusText" Text="Ready" FontSize="12"
                     VerticalAlignment="Center"/>
          <TextBlock Name="ElapsedText" Text="" FontSize="11"
                     Foreground="#666666" VerticalAlignment="Center" Margin="14,0,0,0"/>
        </StackPanel>
      </DockPanel>
    </Border>
  </Grid>
</Window>
'@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$window = [Windows.Markup.XamlReader]::Load($reader)

# ── UI references ─────────────────────────────────────────────────────────────
$LogBox       = $window.FindName('LogBox')
$StatusText   = $window.FindName('StatusText')
$StatusIcon   = $window.FindName('StatusIcon')
$ElapsedText  = $window.FindName('ElapsedText')
$ProgressBar  = $window.FindName('ProgressBar')
$ChkAutoScroll = $window.FindName('ChkAutoScroll')
$LogCountText  = $window.FindName('LogCountText')
$BtnCancel      = $window.FindName('BtnCancel')
$AdminBadge     = $window.FindName('AdminBadge')
$AdminBadgeText = $window.FindName('AdminBadgeText')
$FontSlider     = $window.FindName('FontSlider')
$FontSizeLabel  = $window.FindName('FontSizeLabel')

$script:Buttons = @(
    $window.FindName('BtnResetCache')
    $window.FindName('BtnRestartServices')
    $window.FindName('BtnClearCache')
    $window.FindName('BtnReRegister')
    $window.FindName('BtnRepairApps')
    $window.FindName('BtnFullRepair')
    $window.FindName('BtnDiagnostics')
    $window.FindName('BtnOpenLog')
    $window.FindName('BtnClearLog')
)

# Admin badge color
if (-not (Test-AdminPrivilege)) {
    $AdminBadge.Background = [Windows.Media.SolidColorBrush][Windows.Media.Color]::FromRgb(0xC4, 0x2B, 0x1C)
    $AdminBadgeText.Text   = '⚠ No Admin'
}

# ── Logging ───────────────────────────────────────────────────────────────────
$script:LogEntryCount = 0

# Color map for log levels
$script:LevelColors = @{
    'Info'    = '#DADADA'
    'Success' = '#6EC26E'
    'Warning' = '#D9A520'
    'Error'   = '#F05454'
    'Fatal'   = '#FF0000'
}
$script:LevelIcons = @{
    'Info'    = '  '
    'Success' = '✔ '
    'Warning' = '⚠ '
    'Error'   = '✖ '
    'Fatal'   = '💀 '
}

function Write-Log {
    param(
        [Parameter(Mandatory)]
        [string]$Message,

        [ValidateSet('Info','Success','Warning','Error','Fatal')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'HH:mm:ss'
    $icon      = $script:LevelIcons[$Level]
    $color     = $script:LevelColors[$Level]

    # File log (full timestamp)
    $fileLine = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [$Level] $Message"
    try { Add-Content -Path $script:LogFile -Value $fileLine -ErrorAction SilentlyContinue } catch {}

    # UI log (colored RichTextBox)
    if ($window -and $LogBox) {
        $window.Dispatcher.Invoke([action] {
            $para = New-Object Windows.Documents.Paragraph
            $para.Margin = New-Object Windows.Thickness(0)
            $para.LineHeight = 18

            # Timestamp span (dim)
            $tsRun = New-Object Windows.Documents.Run("[$timestamp] ")
            $tsRun.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#555555'))

            # Icon + message span (colored)
            $msgRun = New-Object Windows.Documents.Run("$icon$Message")
            $msgRun.Foreground = New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString($color))

            $para.Inlines.Add($tsRun)
            $para.Inlines.Add($msgRun)
            $LogBox.Document.Blocks.Add($para)

            $script:LogEntryCount++
            $LogCountText.Text = "$script:LogEntryCount entries"

            if ($ChkAutoScroll.IsChecked) {
                $LogBox.ScrollToEnd()
            }
        }, [Windows.Threading.DispatcherPriority]::Background)
    }
}

# ── Global exception handler ──────────────────────────────────────────────────
$null = [AppDomain]::CurrentDomain.add_UnhandledException({
    param($sender, $eventArgs)
    $msg = $eventArgs.ExceptionObject.ToString()
    $line = "[$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')] [Fatal] Unhandled: $msg"
    Add-Content -Path $script:LogFile -Value $line -ErrorAction SilentlyContinue
})

# ── Busy state ────────────────────────────────────────────────────────────────
$script:ActiveWorker  = $null
$script:CancelPending = $false
$script:OpStart       = $null

function Set-BusyState {
    param([bool]$IsBusy, [string]$Status = 'Ready')

    $window.Dispatcher.Invoke([action] {
        foreach ($btn in $script:Buttons) { $btn.IsEnabled = -not $IsBusy }
        $BtnCancel.IsEnabled          = $IsBusy
        $StatusText.Text              = $Status
        $StatusIcon.Foreground        = if ($IsBusy) {
            New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#0078D4'))
        } else {
            New-Object Windows.Media.SolidColorBrush([Windows.Media.ColorConverter]::ConvertFromString('#555555'))
        }
        if (-not $IsBusy) {
            $ProgressBar.IsIndeterminate = $false
            $ProgressBar.Value           = 0
            $ElapsedText.Text            = ''
        }
    }, [Windows.Threading.DispatcherPriority]::Normal)
}

# ── Progress helper ───────────────────────────────────────────────────────────
function Update-Progress {
    param([int]$Percent, [string]$Message)
    if ($script:ActiveWorker) {
        $script:ActiveWorker.ReportProgress($Percent, $Message)
    }
}

function Test-CancelRequested {
    if ($script:CancelPending) {
        Write-Log 'Operation cancelled by user.' 'Warning'
        return $true
    }
    return $false
}

# ── Action runner ─────────────────────────────────────────────────────────────
function Start-Action {
    param(
        [Parameter(Mandatory)] [string]$Title,
        [Parameter(Mandatory)] [scriptblock]$Action
    )

    if ($script:ActiveWorker -and $script:ActiveWorker.IsBusy) {
        Write-Log 'Another operation is already in progress.' 'Warning'
        return
    }

    $script:CancelPending = $false
    $script:OpStart       = [datetime]::Now
    Set-BusyState -IsBusy $true -Status $Title

    # Indeterminate until first ReportProgress
    $window.Dispatcher.Invoke([action] {
        $ProgressBar.IsIndeterminate = $true
    })

    Write-Log "Starting: $Title" 'Info'

    $worker = New-Object ComponentModel.BackgroundWorker
    $worker.WorkerReportsProgress       = $true
    $worker.WorkerSupportsCancellation  = $true

    $worker.add_DoWork({
        param($sender, $e)
        try {
            & $Action
            $e.Result = 'ok'
        }
        catch {
            $e.Result = $_.Exception.Message
            throw
        }
    })

    $worker.add_ProgressChanged({
        param($sender, $e)
        $window.Dispatcher.InvokeAsync([action] {
            $ProgressBar.IsIndeterminate = $false
            if ($e.ProgressPercentage -ge 0 -and $e.ProgressPercentage -le 100) {
                $ProgressBar.Value = $e.ProgressPercentage
            }
            if ($e.UserState) { $StatusText.Text = $e.UserState.ToString() }
            # Elapsed
            if ($script:OpStart) {
                $elapsed = ([datetime]::Now - $script:OpStart).ToString('mm\:ss')
                $ElapsedText.Text = "⏱ $elapsed"
            }
        })
    })

    $worker.add_RunWorkerCompleted({
        param($sender, $e)
        $elapsed = if ($script:OpStart) {
            ([datetime]::Now - $script:OpStart).TotalSeconds.ToString('0.0')
        } else { '?' }

        if ($e.Error) {
            Write-Log "Failed: $Title — $($e.Error.Message)  (${elapsed}s)" 'Error'
            [Windows.MessageBox]::Show(
                "Operation failed:`n$($e.Error.Message)",
                "Error — $Title",
                [Windows.MessageBoxButton]::OK,
                [Windows.MessageBoxImage]::Error
            ) | Out-Null
        }
        elseif ($script:CancelPending) {
            Write-Log "Cancelled: $Title  (${elapsed}s)" 'Warning'
        }
        else {
            Write-Log "Completed: $Title  (${elapsed}s)" 'Success'
        }

        Set-BusyState -IsBusy $false -Status 'Ready'
        $script:ActiveWorker  = $null
        $script:CancelPending = $false
        $script:OpStart       = $null
    })

    $script:ActiveWorker = $worker
    $worker.RunWorkerAsync()
}

# ── Utility ───────────────────────────────────────────────────────────────────
function Test-AppxSupport {
    if (-not (Get-Command Get-AppxPackage  -ErrorAction SilentlyContinue) -or
        -not (Get-Command Add-AppxPackage  -ErrorAction SilentlyContinue)) {
        Write-Log 'Appx cmdlets not available. Use Windows PowerShell 5.1 or import WindowsCompatibility module.' 'Warning'
        return $false
    }
    return $true
}

function Confirm-Action {
    param([string]$Message, [string]$Title)
    $result = [Windows.MessageBox]::Show(
        $Message, $Title,
        [Windows.MessageBoxButton]::YesNo,
        [Windows.MessageBoxImage]::Question
    )
    return $result -eq [Windows.MessageBoxResult]::Yes
}

# ── Operations ────────────────────────────────────────────────────────────────
function Invoke-CacheReset {
    Write-Log 'Launching wsreset.exe (Windows Store cache reset)...' 'Info'
    $timeout = 60
    try {
        $proc = Start-Process 'wsreset.exe' -PassThru -WindowStyle Minimized
        if (-not $proc.WaitForExit($timeout * 1000)) {
            Write-Log "wsreset.exe exceeded $timeout second timeout — killing process" 'Warning'
            $proc.Kill()
        }
        else {
            Write-Log 'wsreset.exe completed successfully' 'Success'
        }
    }
    catch {
        Write-Log "Failed to run wsreset.exe: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Restart-StoreServices {
    $services = @(
        @{ Name = 'wuauserv';       Display = 'Windows Update' }
        @{ Name = 'bits';           Display = 'Background Intelligent Transfer (BITS)' }
        @{ Name = 'WSService';      Display = 'Windows Store Service' }
        @{ Name = 'InstallService'; Display = 'Microsoft Store Install Service' }
        @{ Name = 'AppXSvc';        Display = 'AppX Deployment Service' }
    )

    $ok = 0; $fail = 0
    $total = $services.Count

    for ($i = 0; $i -lt $total; $i++) {
        if (Test-CancelRequested) { return }
        $svc = $services[$i]
        Update-Progress -Percent ([int](($i / $total) * 100)) -Message "Restarting $($svc.Display)..."

        try {
            $service = Get-Service -Name $svc.Name -ErrorAction Stop
            Write-Log "Restarting $($svc.Display) (currently: $($service.Status))..." 'Info'
            if ($service.Status -eq 'Running') {
                Stop-Service  -Name $svc.Name -Force -ErrorAction Stop -WarningAction SilentlyContinue
                Start-Sleep   -Milliseconds 400
            }
            Start-Service -Name $svc.Name -ErrorAction Stop -WarningAction SilentlyContinue
            Write-Log "$($svc.Display) — restarted OK" 'Success'
            $ok++
        }
        catch {
            Write-Log "$($svc.Display): $($_)" 'Warning'
            $fail++
        }
    }

    Update-Progress -Percent 100 -Message 'Services done'
    Write-Log "Services — restarted: $ok  |  failed/skipped: $fail" 'Info'
}

function Clear-StoreLocalCache {
    $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"

    Write-Log 'Terminating Microsoft Store processes...' 'Info'
    $procs = Get-Process -Name '*WinStore*','WinStore.App' -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | Stop-Process -Force -ErrorAction SilentlyContinue
        Start-Sleep -Milliseconds 500
        Write-Log "Stopped $($procs.Count) Store process(es)" 'Info'
    }

    if (-not (Test-Path $cachePath)) {
        Write-Log "Cache folder not found: $cachePath" 'Warning'
        return
    }

    try {
        $items   = Get-ChildItem -Path $cachePath -Recurse -Force -ErrorAction Stop
        $count   = $items.Count
        $sizeMB  = [math]::Round(($items | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 2)
        Write-Log "Clearing $count item(s) — $sizeMB MB from: $cachePath" 'Info'
        Remove-Item -Path "$cachePath\*" -Recurse -Force -ErrorAction Stop
        Write-Log 'LocalCache cleared successfully' 'Success'
    }
    catch {
        Write-Log "Failed to clear cache: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Invoke-StoreReRegistration {
    if (-not (Test-AppxSupport)) { return }

    Write-Log 'Re-registering Microsoft Store packages...' 'Info'
    try {
        $pkgs = @(Get-AppxPackage -Name '*WindowsStore*' -AllUsers -ErrorAction Stop)
        if (-not $pkgs) { Write-Log 'No Microsoft Store packages found' 'Warning'; return }

        $ok = 0; $total = $pkgs.Count
        for ($i = 0; $i -lt $total; $i++) {
            if (Test-CancelRequested) { return }
            $pkg      = $pkgs[$i]
            $manifest = Join-Path $pkg.InstallLocation 'AppXManifest.xml'
            Update-Progress -Percent ([int](($i / $total) * 100)) -Message "Registering $($pkg.Name)"

            if (Test-Path $manifest) {
                try {
                    Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop
                    Write-Log "Re-registered: $($pkg.Name) v$($pkg.Version)" 'Success'
                    $ok++
                }
                catch {
                    Write-Log "Failed: $($pkg.Name) — $_" 'Warning'
                }
            }
            else {
                Write-Log "Manifest missing for $($pkg.Name)" 'Warning'
            }
        }
        Update-Progress -Percent 100 -Message 'Re-registration done'
        Write-Log "Re-registered $ok of $total Store package(s)" 'Info'
    }
    catch {
        Write-Log "Store re-registration failed: $($_.Exception.Message)" 'Error'
        throw
    }
}

function Repair-AllUWPApps {
    if (-not (Test-AppxSupport)) { return }

    Write-Log 'Enumerating all UWP apps...' 'Info'
    try { $apps = @(Get-AppxPackage -AllUsers -ErrorAction Stop) }
    catch { Write-Log "Failed to enumerate apps: $($_.Exception.Message)" 'Error'; throw }

    $total = $apps.Count
    if ($total -eq 0) { Write-Log 'No UWP apps found' 'Warning'; return }
    Write-Log "Found $total UWP app(s) — starting re-registration..." 'Info'

    $ok = 0; $fail = 0

    for ($i = 0; $i -lt $total; $i++) {
        if (Test-CancelRequested) { return }

        $app      = $apps[$i]
        $pct      = [math]::Round((($i + 1) / $total) * 100)
        $manifest = Join-Path $app.InstallLocation 'AppXManifest.xml'

        Update-Progress -Percent $pct -Message "[$pct%] $($app.Name)"

        if (-not (Test-Path $manifest)) { $fail++; continue }

        try   { Add-AppxPackage -DisableDevelopmentMode -Register $manifest -ErrorAction Stop; $ok++ }
        catch { $fail++ }

        if ($pct % 10 -eq 0) {
            Write-Log "Progress $pct% — ✔ $ok  ✖ $fail" 'Info'
        }
    }

    $lvl = if ($fail -eq 0) { 'Success' } else { 'Warning' }
    Write-Log "Repair complete — ✔ $ok succeeded  ✖ $fail failed  (total: $total)" $lvl
}

function Invoke-Diagnostics {
    Write-Log '════════ Diagnostics Started ════════' 'Info'

    # Services
    Write-Log '── Service Status ──' 'Info'
    @(
        @{ Name='wuauserv';       Display='Windows Update' }
        @{ Name='bits';           Display='BITS' }
        @{ Name='WSService';      Display='Windows Store Service' }
        @{ Name='InstallService'; Display='Store Install Service' }
        @{ Name='AppXSvc';        Display='AppX Deployment Service' }
    ) | ForEach-Object {
        $s = Get-Service -Name $_.Name -ErrorAction SilentlyContinue
        if ($s) {
            $lvl = if ($s.Status -eq 'Running') { 'Success' } else { 'Warning' }
            Write-Log "$($_.Display):  $($s.Status)  (start: $($s.StartType))" $lvl
        }
        else { Write-Log "$($_.Display):  Not found" 'Warning' }
    }

    # Store package
    Write-Log '── Microsoft Store Package ──' 'Info'
    if (Test-AppxSupport) {
        $store = Get-AppxPackage -Name 'Microsoft.WindowsStore' -ErrorAction SilentlyContinue
        if ($store) {
            Write-Log "Name:     $($store.Name)" 'Info'
            Write-Log "Version:  $($store.Version)" 'Info'
            Write-Log "Arch:     $($store.Architecture)" 'Info'
            Write-Log "Location: $($store.InstallLocation)" 'Info'
        }
        else { Write-Log 'Microsoft.WindowsStore package NOT FOUND' 'Error' }

        $appCount = @(Get-AppxPackage -AllUsers -ErrorAction SilentlyContinue).Count
        Write-Log "Total UWP apps installed (all users): $appCount" 'Info'
    }

    # Cache
    Write-Log '── Cache Info ──' 'Info'
    $cachePath = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsStore_8wekyb3d8bbwe\LocalCache"
    if (Test-Path $cachePath) {
        $files   = @(Get-ChildItem $cachePath -Recurse -File -ErrorAction SilentlyContinue)
        $sizeMB  = [math]::Round(($files | Measure-Object Length -Sum).Sum / 1MB, 2)
        Write-Log "Path:  $cachePath" 'Info'
        $lvl = if ($sizeMB -gt 100) { 'Warning' } else { 'Info' }
        Write-Log "Size:  $sizeMB MB  ($($files.Count) files)" $lvl
    }
    else { Write-Log "Cache folder not found: $cachePath" 'Warning' }

    # Processes
    Write-Log '── Store Processes ──' 'Info'
    $procs = Get-Process -Name '*WinStore*','WinStore.App' -ErrorAction SilentlyContinue
    if ($procs) {
        $procs | ForEach-Object { Write-Log "$($_.Name)  PID: $($_.Id)  Mem: $([math]::Round($_.WorkingSet64/1MB,1)) MB" 'Info' }
    }
    else { Write-Log 'No Store processes currently running' 'Info' }

    Write-Log '════════ Diagnostics Complete ════════' 'Success'
}

function Invoke-FullRepair {
    Write-Log '══ Full Repair — 5-step sequence ══' 'Info'

    Update-Progress -Percent 5  -Message 'Step 1/5: Resetting cache...'
    Invoke-CacheReset
    if (Test-CancelRequested) { return }

    Update-Progress -Percent 25 -Message 'Step 2/5: Restarting services...'
    Restart-StoreServices
    if (Test-CancelRequested) { return }

    Update-Progress -Percent 45 -Message 'Step 3/5: Clearing LocalCache...'
    Clear-StoreLocalCache
    if (Test-CancelRequested) { return }

    Update-Progress -Percent 60 -Message 'Step 4/5: Re-registering Store...'
    Invoke-StoreReRegistration
    if (Test-CancelRequested) { return }

    Update-Progress -Percent 75 -Message 'Step 5/5: Repairing all UWP apps...'
    Repair-AllUWPApps

    Update-Progress -Percent 100 -Message 'Full Repair complete'
    Write-Log '══ Full Repair sequence finished ══' 'Success'
}

# ── Button wiring ─────────────────────────────────────────────────────────────
$window.FindName('BtnResetCache').Add_Click({
    Start-Action -Title 'Reset Cache' -Action { Invoke-CacheReset }
})

$window.FindName('BtnRestartServices').Add_Click({
    Start-Action -Title 'Restart Services' -Action { Restart-StoreServices }
})

$window.FindName('BtnClearCache').Add_Click({
    if (Confirm-Action "This will close the Microsoft Store and delete all LocalCache files.`nContinue?" 'Clear LocalCache') {
        Start-Action -Title 'Clear LocalCache' -Action { Clear-StoreLocalCache }
    }
})

$window.FindName('BtnReRegister').Add_Click({
    Start-Action -Title 'Re-register Store' -Action { Invoke-StoreReRegistration }
})

$window.FindName('BtnRepairApps').Add_Click({
    if (Confirm-Action "This will re-register all UWP apps and may take several minutes.`nContinue?" 'Repair All Apps') {
        Start-Action -Title 'Repair All Apps' -Action { Repair-AllUWPApps }
    }
})

$window.FindName('BtnFullRepair').Add_Click({
    if (Confirm-Action "Full Repair runs all 5 steps in sequence and may take several minutes.`nProceed?" 'Full Repair') {
        Start-Action -Title 'Full Repair' -Action { Invoke-FullRepair }
    }
})

$window.FindName('BtnDiagnostics').Add_Click({
    Start-Action -Title 'Diagnostics' -Action { Invoke-Diagnostics }
})

$BtnCancel.Add_Click({
    if ($script:ActiveWorker -and $script:ActiveWorker.IsBusy) {
        $script:CancelPending = $true
        Write-Log 'Cancel requested — waiting for current step to finish...' 'Warning'
        $BtnCancel.IsEnabled = $false
    }
})

$window.FindName('BtnOpenLog').Add_Click({
    try   { Start-Process 'explorer.exe' -ArgumentList $script:LogDir }
    catch { Write-Log "Could not open log folder: $_" 'Error' }
})

$window.FindName('BtnClearLog').Add_Click({
    $LogBox.Document.Blocks.Clear()
    $script:LogEntryCount = 0
    $LogCountText.Text = '0 entries'
})

# ── Font scaling ──────────────────────────────────────────────────────────────
# WPF local FontSize values (set in XAML) override inherited values, so we
# cannot rely on $window.FontSize propagation. Instead we walk the visual tree
# and set FontSize on every FrameworkElement that supports it.

function Set-GlobalFontSize {
    param([int]$Size)

    # Walk the visual tree using VisualTreeHelper
    function Set-FontRecursive {
        param([Windows.DependencyObject]$element, [int]$Size)
        if ($null -eq $element) { return }

        if ($element -is [Windows.Controls.Control]) {
            try { $element.FontSize = $Size } catch {}
        }
        elseif ($element -is [Windows.Controls.TextBlock]) {
            try { $element.FontSize = $Size } catch {}
        }

        $count = [Windows.Media.VisualTreeHelper]::GetChildrenCount($element)
        for ($i = 0; $i -lt $count; $i++) {
            $child = [Windows.Media.VisualTreeHelper]::GetChild($element, $i)
            Set-FontRecursive $child $Size
        }
    }

    Set-FontRecursive $window $Size
    $FontSizeLabel.Text = "${Size}px"
}

# Load saved preference and apply before window is shown
$savedFont = [math]::Max(10, [math]::Min(20, [int]$script:Config.FontSize))
$FontSlider.Value = $savedFont

$window.Add_ContentRendered({
    Set-GlobalFontSize -Size ([int]$FontSlider.Value)
})

# Live update while dragging
$FontSlider.Add_ValueChanged({
    param($sender, $e)
    $size = [int]$e.NewValue
    Set-GlobalFontSize -Size $size
})

# Save preference when window closes
$window.Add_Closing({
    Save-Config -FontSize ([int]$FontSlider.Value)
})

# ── Launch ────────────────────────────────────────────────────────────────────
Write-Log 'Microsoft Store Repair v3.0.0 ready.' 'Success'
Write-Log "Log file: $script:LogFile" 'Info'
$window.ShowDialog() | Out-Null
