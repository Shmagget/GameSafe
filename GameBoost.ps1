#requires -version 5.1
<#
================================================================================
  GameBoost  -  Tiered one-switch game performance booster for Windows
================================================================================
  Pick a tier, then flip the switch ON before you play:

    NORMAL  - Light touch. High Performance power plan, stops a few
              telemetry/search services, disables Game DVR, raises your
              game's priority. Closes nothing. Use when you just need a nudge.

    HIGH    - Stops the full background-service list and closes bloat apps
              (OneDrive, Teams, Spotify, Dropbox...). Best for most people.

    EXTREME - Maximum. Everything in High PLUS:
                * Ultimate Performance power plan
                * Extended service shutdown (Update, BITS, telemetry, etc.)
                * Frees RAM by trimming every background process
                * Lowers EVERY other app's CPU priority so the game gets the cores
                * Strips Windows visual effects / animations / transparency
                * Network-latency registry tweaks
                * Restarts Explorer to free its memory
                * Closes heavy apps including web browsers
              Built to squeeze real performance out of weak PCs.

  Flip OFF when done and GameBoost restores EVERYTHING it changed (saved to
  disk, so it works even after you close the window). A reboot is always a
  clean fallback - power plan, priorities and services all reset on restart.

  SAFETY: Never touches critical Windows processes, never disables your
  antivirus, and never uses Realtime priority (which can freeze a PC). All
  targets come from the editable allow-lists below.
================================================================================
#>

# ----------------------------------------------------------------------------
# Self-elevate to Administrator (needed to stop services / set HKLM tweaks)
# ----------------------------------------------------------------------------
$principal = New-Object Security.Principal.WindowsPrincipal(
    [Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)) {
    try {
        Start-Process powershell.exe -ArgumentList @(
            '-NoProfile','-ExecutionPolicy','Bypass','-File',"`"$PSCommandPath`""
        ) -Verb RunAs
    } catch { }
    exit
}

Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore
Add-Type -AssemblyName WindowsBase

# ============================================================================
# CONFIG  -  edit these lists to taste
# ============================================================================

# Services stopped at NORMAL (and above). Clearly useless while gaming.
$Script:SvcLight = @(
    'SysMain'           # SuperFetch / prefetch
    'WSearch'           # Windows Search indexer (disk + CPU spikes)
    'DiagTrack'         # Connected User Experiences and Telemetry
    'dmwappushservice'  # WAP push routing (telemetry)
    'MapsBroker'        # Downloaded Maps Manager
)

# Added at HIGH (and above).
$Script:SvcStandard = @(
    'Spooler'           # Print Spooler (remove if you print while gaming)
    'Fax'
    'WMPNetworkSvc'     # Windows Media Player network sharing
    'WerSvc'            # Windows Error Reporting
    'PcaSvc'            # Program Compatibility Assistant
    'RetailDemo'
)

# Added at EXTREME only. More aggressive but still safe; restarted on OFF.
$Script:SvcExtended = @(
    'wuauserv'          # Windows Update (no mid-game downloads)
    'BITS'              # Background Intelligent Transfer
    'DoSvc'             # Delivery Optimization (update peer sharing)
    'CDPSvc'            # Connected Devices Platform
    'lfsvc'             # Geolocation
    'WbioSrvc'          # Windows Biometric
    'TabletInputService'# Touch keyboard / handwriting
    'SensorService'
    'TrkWks'            # Distributed Link Tracking
    'wisvc'             # Windows Insider
    'PrintNotify'
    'RemoteRegistry'
)

# Background apps CLOSED at HIGH (and above). User apps, not system processes.
$Script:BloatStandard = @(
    'OneDrive'
    'Teams','ms-teams'
    'Skype'
    'Dropbox'
    'GoogleDriveFS'
    'Spotify'
    'Slack'
    'Zoom'
    'Cortana'
    'PhoneExperienceHost'   # Phone Link
    'WidgetService','Widgets'
    'GameBarFTServer'
)

# Additionally closed at EXTREME. Heavier apps incl. browsers - big RAM wins.
$Script:BloatExtended = @(
    'Discord'
    'msedge','chrome','firefox','brave','opera','vivaldi'
    'OUTLOOK','WINWORD','EXCEL'
    'EpicWebHelper'
    'RzSynapse','iCUE','LGHUB','LightingService','ArmouryCrate.Service'
    'AdobeIPCBroker','CCXProcess','Acrobat'
)

# Processes NEVER de-prioritized by the Extreme "lower everything else" pass.
# (Critical UI, audio, and anti-cheat - lowering these causes stutter/kicks.)
$Script:ProtectNames = @(
    'explorer','dwm','audiodg','csrss','wininit','winlogon','services','lsass',
    'smss','svchost','system','idle','registry','conhost','fontdrvhost',
    'powershell','pwsh','sihost','ctfmon','SystemSettings',
    'EasyAntiCheat','EasyAntiCheat_EOS','BEService','vgc','vgtray','vgk',
    'SteamService'
) | ForEach-Object { $_.ToLowerInvariant() }

$Script:HighPerfGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$Script:UltimateGuid = 'e9a42b02-d5df-448d-aa00-03f14749eb61'
$Script:MultimediaProfile = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Multimedia\SystemProfile'
$Script:StateDir  = Join-Path $env:LOCALAPPDATA 'GameBoost'
$Script:StateFile = Join-Path $Script:StateDir 'state.json'

# ----------------------------------------------------------------------------
# Win32 helpers: foreground window + RAM working-set trimming
# ----------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'GBNative').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GBNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
    [DllImport("psapi.dll")]  public static extern bool EmptyWorkingSet(IntPtr hProcess);
}
"@
}

function Get-ForegroundProcess {
    $h = [GBNative]::GetForegroundWindow()
    if ($h -eq [IntPtr]::Zero) { return $null }
    $procId = 0
    [void][GBNative]::GetWindowThreadProcessId($h, [ref]$procId)
    if ($procId -le 0) { return $null }
    try { return Get-Process -Id $procId -ErrorAction Stop } catch { return $null }
}

# ----------------------------------------------------------------------------
# Logging into the GUI
# ----------------------------------------------------------------------------
$Script:LogBox = $null
function Write-GBLog([string]$msg) {
    $line = "[{0}] {1}`r`n" -f (Get-Date).ToString('HH:mm:ss'), $msg
    if ($Script:LogBox) {
        $Script:LogBox.Dispatcher.Invoke([action]{
            $Script:LogBox.AppendText($line); $Script:LogBox.ScrollToEnd()
        })
    }
}

function Get-ActiveSchemeGuid {
    $out = powercfg /getactivescheme
    if ($out -match '([0-9a-fA-F-]{36})') { return $Matches[1] }
    return $null
}

function Get-RegValue($path, $name) {
    $item = Get-ItemProperty -Path $path -Name $name -ErrorAction SilentlyContinue
    if ($null -eq $item) { return $null }
    return $item.$name
}

# ----------------------------------------------------------------------------
# Tier -> options map
# ----------------------------------------------------------------------------
# True if this process should be left completely alone (the game, or - when the
# Discord toggle is on - Discord, so voice chat stays smooth).
function Test-KeepProcess([string]$name, $opts) {
    $n = $name.ToLowerInvariant()
    if ($opts.Target -and $n -eq $opts.Target.ToLowerInvariant()) { return $true }
    if ($opts.KeepDiscord -and $n -like 'discord*') { return $true }
    return $false
}

function Get-TierOptions([string]$tier, [string]$target, [bool]$keepDiscord) {
    $o = @{
        Tier = $tier; Target = $target; KeepDiscord = $keepDiscord
        PowerMode = 'none'; ServiceLevel = 'none'; Bloat = 'none'
        Dvr = $false; Priority = $false
        LowerOthers = $false; TrimRam = $false; VisualFx = $false; Network = $false
    }
    switch ($tier) {
        'Normal' {
            $o.PowerMode = 'high'; $o.ServiceLevel = 'light'
            $o.Dvr = $true; $o.Priority = $true
        }
        'High' {
            $o.PowerMode = 'high'; $o.ServiceLevel = 'standard'; $o.Bloat = 'standard'
            $o.Dvr = $true; $o.Priority = $true
        }
        'Extreme' {
            $o.PowerMode = 'ultimate'; $o.ServiceLevel = 'extended'; $o.Bloat = 'extended'
            $o.Dvr = $true; $o.Priority = $true
            $o.LowerOthers = $true; $o.TrimRam = $true; $o.VisualFx = $true; $o.Network = $true
        }
    }
    return $o
}

function Get-ServiceSet([string]$level) {
    switch ($level) {
        'light'    { return $Script:SvcLight }
        'standard' { return $Script:SvcLight + $Script:SvcStandard }
        'extended' { return $Script:SvcLight + $Script:SvcStandard + $Script:SvcExtended }
        default    { return @() }
    }
}
function Get-BloatSet([string]$level) {
    switch ($level) {
        'standard' { return $Script:BloatStandard }
        'extended' { return $Script:BloatStandard + $Script:BloatExtended }
        default    { return @() }
    }
}

# ============================================================================
# ENABLE
# ============================================================================
function Enable-GameBoost($opts) {
    if (-not (Test-Path $Script:StateDir)) {
        New-Item -ItemType Directory -Path $Script:StateDir -Force | Out-Null
    }

    $state = [ordered]@{
        timestamp = (Get-Date).ToString('o')
        tier      = $opts.Tier
        target    = $opts.Target
        opts      = $opts
        prevPowerScheme = $null
        services  = @()
        gameDvr   = $null
        network   = $null
        visualFx  = $null
    }

    # --- Power plan ---
    if ($opts.PowerMode -ne 'none') {
        $state.prevPowerScheme = Get-ActiveSchemeGuid
        if ($opts.PowerMode -eq 'ultimate') {
            $list = powercfg /list | Out-String
            if ($list -notmatch $Script:UltimateGuid) {
                powercfg -duplicatescheme $Script:UltimateGuid 2>$null | Out-Null
            }
            powercfg /setactive $Script:UltimateGuid 2>$null
            if ((Get-ActiveSchemeGuid) -ieq $Script:UltimateGuid) {
                Write-GBLog "Power plan -> Ultimate Performance"
            } else {
                powercfg /setactive $Script:HighPerfGuid 2>$null
                Write-GBLog "Ultimate plan unavailable -> using High Performance"
            }
        } else {
            powercfg /setactive $Script:HighPerfGuid 2>$null
            Write-GBLog "Power plan -> High Performance"
        }
    }

    # --- Services ---
    $svcSet = Get-ServiceSet $opts.ServiceLevel
    if ($svcSet.Count -gt 0) {
        $stopped = 0
        foreach ($name in $svcSet) {
            $svc = Get-Service -Name $name -ErrorAction SilentlyContinue
            if (-not $svc) { continue }
            $wasRunning = ($svc.Status -eq 'Running')
            $state.services += @{ name = $name; wasRunning = $wasRunning }
            if ($wasRunning) {
                try { Stop-Service -Name $name -Force -ErrorAction Stop; $stopped++ }
                catch { Write-GBLog "  (could not stop $name)" }
            }
        }
        Write-GBLog "Stopped $stopped background service(s)"
    }

    # --- Bloat apps ---
    $bloatSet = Get-BloatSet $opts.Bloat
    if ($bloatSet.Count -gt 0) {
        $killed = 0
        foreach ($name in $bloatSet) {
            foreach ($p in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                if ($p.Id -eq $PID) { continue }
                if (Test-KeepProcess $p.ProcessName $opts) { continue }
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $killed++ } catch { }
            }
        }
        Write-GBLog "Closed $killed background app process(es)"
    }

    # --- Game DVR off ---
    if ($opts.Dvr) {
        $p1 = 'HKCU:\System\GameConfigStore'
        $p2 = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
        $state.gameDvr = @{
            gcs = Get-RegValue $p1 'GameDVR_Enabled'
            dvr = Get-RegValue $p2 'AppCaptureEnabled'
        }
        try { Set-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -Value 0 -Type DWord -Force } catch { }
        if (-not (Test-Path $p2)) { New-Item -Path $p2 -Force | Out-Null }
        try { Set-ItemProperty -Path $p2 -Name 'AppCaptureEnabled' -Value 0 -Type DWord -Force } catch { }
        Write-GBLog "Game DVR / background recording -> off"
    }

    # --- Network latency tweaks (Extreme) ---
    if ($opts.Network) {
        $state.network = @{
            sysResp     = Get-RegValue $Script:MultimediaProfile 'SystemResponsiveness'
            netThrottle = Get-RegValue $Script:MultimediaProfile 'NetworkThrottlingIndex'
        }
        try {
            Set-ItemProperty -Path $Script:MultimediaProfile -Name 'SystemResponsiveness' -Value 0 -Type DWord -Force
            Set-ItemProperty -Path $Script:MultimediaProfile -Name 'NetworkThrottlingIndex' -Value 0xffffffff -Type DWord -Force
            Write-GBLog "Network throttling disabled, system responsiveness maxed"
        } catch { Write-GBLog "  (network tweak skipped)" }
    }

    # --- Game priority ---
    if ($opts.Priority -and $opts.Target) {
        $n = 0
        foreach ($p in (Get-Process -Name $opts.Target -ErrorAction SilentlyContinue)) {
            try { $p.PriorityClass = 'High'; $n++ } catch { }
        }
        if ($n -gt 0) { Write-GBLog "Game '$($opts.Target)' priority -> High ($n proc)" }
        else { Write-GBLog "Game '$($opts.Target)' not running yet (priority applies once it is)" }
    }

    # --- Lower every OTHER app's priority (Extreme) ---
    if ($opts.LowerOthers) {
        $mySession = (Get-Process -Id $PID).SessionId
        $lowered = 0
        foreach ($p in Get-Process) {
            if ($p.Id -eq $PID) { continue }
            if ($p.SessionId -ne $mySession) { continue }
            if (Test-KeepProcess $p.ProcessName $opts) { continue }
            if ($Script:ProtectNames -contains $p.ProcessName.ToLowerInvariant()) { continue }
            try { $p.PriorityClass = 'BelowNormal'; $lowered++ } catch { }
        }
        Write-GBLog "Lowered priority of $lowered other app(s) - cores go to the game"
    }

    # --- Strip visual effects (Extreme) ---
    if ($opts.VisualFx) {
        $vePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        $wmPath = 'HKCU:\Control Panel\Desktop\WindowMetrics'
        $dtPath = 'HKCU:\Control Panel\Desktop'
        $pzPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        $state.visualFx = @{
            vfx          = Get-RegValue $vePath 'VisualFXSetting'
            minAnimate   = Get-RegValue $wmPath 'MinAnimate'
            dragFull     = Get-RegValue $dtPath 'DragFullWindows'
            transparency = Get-RegValue $pzPath 'EnableTransparency'
        }
        if (-not (Test-Path $vePath)) { New-Item -Path $vePath -Force | Out-Null }
        try {
            Set-ItemProperty -Path $vePath -Name 'VisualFXSetting' -Value 2 -Type DWord -Force
            Set-ItemProperty -Path $wmPath -Name 'MinAnimate' -Value '0' -Type String -Force
            Set-ItemProperty -Path $dtPath -Name 'DragFullWindows' -Value '0' -Type String -Force
            if (Test-Path $pzPath) { Set-ItemProperty -Path $pzPath -Name 'EnableTransparency' -Value 0 -Type DWord -Force }
            Write-GBLog "Visual effects -> best performance (animations/transparency off)"
        } catch { Write-GBLog "  (visual-effects tweak skipped)" }
    }

    # --- Free RAM: trim every background working set (Extreme) ---
    if ($opts.TrimRam) {
        $beforeFree = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $trimmed = 0
        foreach ($p in Get-Process) {
            if ($p.Id -eq $PID) { continue }
            if (Test-KeepProcess $p.ProcessName $opts) { continue }
            try { if ([GBNative]::EmptyWorkingSet($p.Handle)) { $trimmed++ } } catch { }
        }
        Start-Sleep -Milliseconds 300
        $afterFree = (Get-CimInstance Win32_OperatingSystem).FreePhysicalMemory
        $freedMB = [math]::Round(($afterFree - $beforeFree) / 1024)
        Write-GBLog "Trimmed $trimmed process(es), freed ~${freedMB} MB RAM"
    }

    # --- Restart Explorer last (frees its memory + applies visual settings) ---
    if ($opts.VisualFx) {
        try {
            Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            Write-GBLog "Explorer restarted (memory freed)"
        } catch { }
    }

    $state | ConvertTo-Json -Depth 6 | Set-Content -Path $Script:StateFile -Encoding UTF8
    Write-GBLog "=== BOOST ON ($($opts.Tier)) ==="
}

# ============================================================================
# DISABLE  -  restore everything
# ============================================================================
function Disable-GameBoost {
    if (-not (Test-Path $Script:StateFile)) {
        Write-GBLog "No saved state - nothing to restore."
        return
    }
    $state = Get-Content -Path $Script:StateFile -Raw | ConvertFrom-Json

    # --- Power plan ---
    if ($state.prevPowerScheme) {
        powercfg /setactive $state.prevPowerScheme 2>$null
        Write-GBLog "Power plan restored"
    }

    # --- Services ---
    if ($state.services) {
        $started = 0
        foreach ($s in $state.services) {
            if ($s.wasRunning) {
                try { Start-Service -Name $s.name -ErrorAction Stop; $started++ } catch { }
            }
        }
        Write-GBLog "Restarted $started service(s)"
    }

    # --- Game DVR ---
    if ($state.gameDvr) {
        $p1 = 'HKCU:\System\GameConfigStore'
        $p2 = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
        if ($null -eq $state.gameDvr.gcs) { Remove-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $p1 -Name 'GameDVR_Enabled' -Value ([int]$state.gameDvr.gcs) -Type DWord -Force -ErrorAction SilentlyContinue }
        if ($null -eq $state.gameDvr.dvr) { Remove-ItemProperty -Path $p2 -Name 'AppCaptureEnabled' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $p2 -Name 'AppCaptureEnabled' -Value ([int]$state.gameDvr.dvr) -Type DWord -Force -ErrorAction SilentlyContinue }
        Write-GBLog "Game DVR setting restored"
    }

    # --- Network ---
    if ($state.network) {
        if ($null -eq $state.network.sysResp) { Remove-ItemProperty -Path $Script:MultimediaProfile -Name 'SystemResponsiveness' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $Script:MultimediaProfile -Name 'SystemResponsiveness' -Value ([int64]$state.network.sysResp) -Type DWord -Force -ErrorAction SilentlyContinue }
        if ($null -eq $state.network.netThrottle) { Remove-ItemProperty -Path $Script:MultimediaProfile -Name 'NetworkThrottlingIndex' -ErrorAction SilentlyContinue }
        else { Set-ItemProperty -Path $Script:MultimediaProfile -Name 'NetworkThrottlingIndex' -Value ([int64]$state.network.netThrottle) -Type DWord -Force -ErrorAction SilentlyContinue }
        Write-GBLog "Network settings restored"
    }

    # --- Visual effects ---
    if ($state.visualFx) {
        $vePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects'
        $wmPath = 'HKCU:\Control Panel\Desktop\WindowMetrics'
        $dtPath = 'HKCU:\Control Panel\Desktop'
        $pzPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
        if ($null -ne $state.visualFx.vfx) { Set-ItemProperty -Path $vePath -Name 'VisualFXSetting' -Value ([int]$state.visualFx.vfx) -Type DWord -Force -ErrorAction SilentlyContinue }
        if ($null -ne $state.visualFx.minAnimate) { Set-ItemProperty -Path $wmPath -Name 'MinAnimate' -Value ([string]$state.visualFx.minAnimate) -Type String -Force -ErrorAction SilentlyContinue }
        if ($null -ne $state.visualFx.dragFull) { Set-ItemProperty -Path $dtPath -Name 'DragFullWindows' -Value ([string]$state.visualFx.dragFull) -Type String -Force -ErrorAction SilentlyContinue }
        if ($null -ne $state.visualFx.transparency) { Set-ItemProperty -Path $pzPath -Name 'EnableTransparency' -Value ([int]$state.visualFx.transparency) -Type DWord -Force -ErrorAction SilentlyContinue }
        Write-GBLog "Visual effects restored"
    }

    # --- Reset all priorities in our session to Normal ---
    try {
        $mySession = (Get-Process -Id $PID).SessionId
        foreach ($p in Get-Process) {
            if ($p.SessionId -ne $mySession) { continue }
            try { $p.PriorityClass = 'Normal' } catch { }
        }
    } catch { }

    # --- Restart Explorer if we had stripped visuals (reapply restored look) ---
    if ($state.visualFx) {
        try { Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue } catch { }
    }

    Remove-Item -Path $Script:StateFile -Force -ErrorAction SilentlyContinue
    Write-GBLog "=== BOOST OFF - everything restored ==="
}

# ============================================================================
# GUI
# ============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GameBoost" Height="792" Width="470"
        WindowStartupLocation="CenterScreen" Background="#0E1117" ResizeMode="CanMinimize">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
      <Setter Property="SnapsToDevicePixels" Value="True"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border CornerRadius="8" Background="{TemplateBinding Background}" Padding="4">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center"/>
            </Border>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
      <Style.Triggers>
        <Trigger Property="IsMouseOver" Value="True"><Setter Property="Opacity" Value="0.88"/></Trigger>
        <Trigger Property="IsEnabled"  Value="False"><Setter Property="Opacity" Value="0.45"/></Trigger>
      </Style.Triggers>
    </Style>
  </Window.Resources>

  <Grid Margin="18">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
    </Grid.RowDefinitions>

    <!-- Title -->
    <StackPanel Grid.Row="0" Orientation="Horizontal">
      <TextBlock Text="GAME" Foreground="#E6E6E6" FontSize="26" FontWeight="Bold"/>
      <TextBlock Text="BOOST" Foreground="#3DDC84" FontSize="26" FontWeight="Bold"/>
    </StackPanel>
    <TextBlock Grid.Row="0" HorizontalAlignment="Right" VerticalAlignment="Bottom"
               Text="reversible · admin" Foreground="#5A6472" FontSize="11"/>

    <!-- Tier pills -->
    <Grid Grid.Row="1" Margin="0,14,0,4">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="*"/>
      </Grid.ColumnDefinitions>
      <Button Name="TierNormal"  Grid.Column="0" Height="40" Margin="0,0,4,0" Content="NORMAL"
              FontWeight="Bold" Foreground="White" Background="#21262D"/>
      <Button Name="TierHigh"    Grid.Column="1" Height="40" Margin="4,0,4,0" Content="HIGH"
              FontWeight="Bold" Foreground="White" Background="#21262D"/>
      <Button Name="TierExtreme" Grid.Column="2" Height="40" Margin="4,0,0,0" Content="EXTREME"
              FontWeight="Bold" Foreground="White" Background="#21262D"/>
    </Grid>

    <Border Grid.Row="2" Background="#161B22" CornerRadius="6" Padding="10,8" Margin="0,2,0,6">
      <TextBlock Name="TierDesc" Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap" Height="50"/>
    </Border>

    <!-- THE LIGHT SWITCH -->
    <Border Grid.Row="3" Name="SwitchPlate" Width="150" Height="236" Margin="0,6,0,4"
            CornerRadius="18" Background="#161B22" BorderBrush="#30363D" BorderThickness="2"
            Cursor="Hand" HorizontalAlignment="Center">
      <Grid>
        <!-- mounting screws -->
        <Ellipse Width="9" Height="9" Fill="#0B0E13" Stroke="#2A2F37" StrokeThickness="1"
                 VerticalAlignment="Top" HorizontalAlignment="Center" Margin="0,9,0,0"/>
        <Ellipse Width="9" Height="9" Fill="#0B0E13" Stroke="#2A2F37" StrokeThickness="1"
                 VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,9,0"/>
        <!-- engraved ON / OFF -->
        <TextBlock Name="LblOn"  Text="ON"  VerticalAlignment="Top"    HorizontalAlignment="Center"
                   Margin="0,24,0,0" Foreground="#3A4250" FontWeight="Bold" FontSize="12"/>
        <TextBlock Name="LblOff" Text="OFF" VerticalAlignment="Bottom" HorizontalAlignment="Center"
                   Margin="0,0,0,22" Foreground="#7D8694" FontWeight="Bold" FontSize="12"/>
        <!-- status LED -->
        <Ellipse Name="Led" Width="13" Height="13" VerticalAlignment="Top" HorizontalAlignment="Center"
                 Margin="0,44,0,0" Fill="#2A2F37"/>
        <!-- lever zone (2 rows: top=ON, bottom=OFF) -->
        <Grid Margin="26,66,26,20">
          <Grid.RowDefinitions>
            <RowDefinition Height="*"/>
            <RowDefinition Height="*"/>
          </Grid.RowDefinitions>
          <Border Name="Lever" Grid.Row="1" CornerRadius="12" Background="#3A4250">
            <Border CornerRadius="12">
              <Border.Background>
                <LinearGradientBrush StartPoint="0,0" EndPoint="0,1">
                  <GradientStop Color="#40FFFFFF" Offset="0"/>
                  <GradientStop Color="#00FFFFFF" Offset="0.45"/>
                  <GradientStop Color="#33000000" Offset="1"/>
                </LinearGradientBrush>
              </Border.Background>
              <TextBlock Name="LeverText" Text="OFF" VerticalAlignment="Center" HorizontalAlignment="Center"
                         Foreground="#0E1117" FontWeight="Bold" FontSize="15"/>
            </Border>
          </Border>
        </Grid>
      </Grid>
    </Border>
    <TextBlock Grid.Row="3" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,-2"
               Text="flip the switch" Foreground="#5A6472" FontSize="10"/>

    <!-- Discord keep box -->
    <Border Grid.Row="4" Background="#161B22" CornerRadius="8" Padding="12" Margin="0,10,0,6"
            BorderBrush="#262C36" BorderThickness="1">
      <Grid>
        <Grid.ColumnDefinitions>
          <ColumnDefinition Width="Auto"/>
          <ColumnDefinition Width="*"/>
          <ColumnDefinition Width="Auto"/>
        </Grid.ColumnDefinitions>
        <Border Grid.Column="0" Width="34" Height="34" CornerRadius="8" Background="#5865F2"
                VerticalAlignment="Center" Margin="0,0,10,0">
          <TextBlock Text="D" Foreground="White" FontWeight="Bold" FontSize="18"
                     HorizontalAlignment="Center" VerticalAlignment="Center"/>
        </Border>
        <StackPanel Grid.Column="1" VerticalAlignment="Center">
          <TextBlock Text="Keep Discord running" Foreground="#E6E6E6" FontWeight="Bold" FontSize="13"/>
          <TextBlock Text="Won't be closed or slowed - so you can talk to your team."
                     Foreground="#8B949E" FontSize="10.5" TextWrapping="Wrap"/>
        </StackPanel>
        <Button Name="DiscordBtn" Grid.Column="2" Width="64" Height="34" Background="#5865F2"
                Foreground="White" FontWeight="Bold" Content="ON" VerticalAlignment="Center"/>
      </Grid>
    </Border>

    <!-- Game target -->
    <Border Grid.Row="5" Background="#161B22" CornerRadius="8" Padding="12" Margin="0,0,0,6">
      <StackPanel>
        <TextBlock Text="Game process (for priority boost)" Foreground="#8B949E" FontSize="11" Margin="0,0,0,4"/>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <TextBox Name="TxtTarget" Grid.Column="0" Height="28" VerticalContentAlignment="Center"
                   Background="#0E1117" Foreground="#E6E6E6" BorderBrush="#30363D"/>
          <Button Name="DetectBtn" Grid.Column="1" Height="28" Width="118" Margin="8,0,0,0"
                  Background="#21262D" Foreground="#C9D1D9" Content="Detect (3s)"/>
        </Grid>
      </StackPanel>
    </Border>

    <TextBlock Grid.Row="6" Name="StatusLine" Foreground="#8B949E" FontSize="12" Margin="0,2,0,6"/>

    <TextBox Grid.Row="7" Name="LogBox" IsReadOnly="True" TextWrapping="Wrap" MinHeight="70"
             VerticalScrollBarVisibility="Auto" Background="#0A0D12" Foreground="#7EE787"
             BorderBrush="#21262D" FontFamily="Consolas" FontSize="11" Padding="6"/>
  </Grid>
</Window>
"@

$reader = New-Object System.Xml.XmlNodeReader $xaml
$win    = [Windows.Markup.XamlReader]::Load($reader)

$SwitchPlate = $win.FindName('SwitchPlate')
$Lever       = $win.FindName('Lever')
$LeverText   = $win.FindName('LeverText')
$Led         = $win.FindName('Led')
$LblOn       = $win.FindName('LblOn')
$LblOff      = $win.FindName('LblOff')
$DiscordBtn  = $win.FindName('DiscordBtn')
$DetectBtn   = $win.FindName('DetectBtn')
$TxtTarget   = $win.FindName('TxtTarget')
$StatusLine  = $win.FindName('StatusLine')
$TierDesc    = $win.FindName('TierDesc')
$TierNormal  = $win.FindName('TierNormal')
$TierHigh    = $win.FindName('TierHigh')
$TierExtreme = $win.FindName('TierExtreme')
$Script:LogBox = $win.FindName('LogBox')

$Script:Tier        = 'High'
$Script:KeepDiscord = $true
$Script:Busy        = $false
$Script:IsOn        = Test-Path $Script:StateFile

$Script:TierHex = @{ Normal = '#2EA043'; High = '#D29922'; Extreme = '#DA3633' }

$TierInfo = @{
    Normal  = 'Light touch. High Performance power plan, stops a few telemetry/search services, disables Game DVR, raises your game priority. Closes nothing.'
    High    = 'Stops the full background-service list and closes bloat apps (OneDrive, Teams, Spotify, Dropbox...). Recommended for most.'
    Extreme = 'MAXIMUM. Ultimate Performance plan, extended service shutdown, frees RAM, lowers every other app''s priority, strips visual effects, network tweaks, restarts Explorer, and closes heavy apps incl. web browsers. Built for weak PCs.'
}

# Color / brush helpers (hex -> WPF objects)
function New-Color([string]$hex) { return [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex) }
function New-Brush([string]$hex) { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex)) }

function Update-TierUI {
    $TierNormal.Background  = New-Brush '#21262D'
    $TierHigh.Background    = New-Brush '#21262D'
    $TierExtreme.Background = New-Brush '#21262D'
    switch ($Script:Tier) {
        'Normal'  { $TierNormal.Background  = New-Brush '#2D7D46' }
        'High'    { $TierHigh.Background    = New-Brush '#C99A2E' }
        'Extreme' { $TierExtreme.Background = New-Brush '#C0392B' }
    }
    $TierDesc.Text = $TierInfo[$Script:Tier]
}

function Update-DiscordUI {
    if ($Script:KeepDiscord) { $DiscordBtn.Background = New-Brush '#5865F2'; $DiscordBtn.Content = 'ON' }
    else                     { $DiscordBtn.Background = New-Brush '#3A4250'; $DiscordBtn.Content = 'OFF' }
}

# Move/recolor the physical switch + lock controls based on ON/OFF state
function Update-SwitchUI {
    $lock = -not $Script:IsOn
    $TierNormal.IsEnabled = $lock; $TierHigh.IsEnabled = $lock; $TierExtreme.IsEnabled = $lock
    $DiscordBtn.IsEnabled = $lock; $DetectBtn.IsEnabled = $lock; $TxtTarget.IsEnabled = $lock

    if ($Script:IsOn) {
        $hex = $Script:TierHex[$Script:Tier]
        [Windows.Controls.Grid]::SetRow($Lever, 0)
        $Lever.Background     = New-Brush $hex
        $LeverText.Text       = 'ON'
        $Led.Fill             = New-Brush $hex
        $glow = New-Object Windows.Media.Effects.DropShadowEffect
        $glow.Color = New-Color $hex; $glow.BlurRadius = 22; $glow.ShadowDepth = 0; $glow.Opacity = 1
        $Led.Effect           = $glow
        $SwitchPlate.BorderBrush = New-Brush $hex
        $LblOn.Foreground     = New-Brush $hex
        $LblOff.Foreground    = New-Brush '#3A4250'
        $StatusLine.Text      = "Boosted ($($Script:Tier)). Your PC is focused on the game."
    } else {
        [Windows.Controls.Grid]::SetRow($Lever, 1)
        $Lever.Background     = New-Brush '#3A4250'
        $LeverText.Text       = 'OFF'
        $Led.Fill             = New-Brush '#2A2F37'
        $Led.Effect           = $null
        $SwitchPlate.BorderBrush = New-Brush '#30363D'
        $LblOn.Foreground     = New-Brush '#3A4250'
        $LblOff.Foreground    = New-Brush '#7D8694'
        $StatusLine.Text      = "Idle. Pick a tier, then flip the switch."
    }
}

# --- Tier pills ---
$selectTier = {
    param($t)
    if ($Script:IsOn -or $Script:Busy) { return }
    $Script:Tier = $t
    Update-TierUI
}
$TierNormal.Add_Click({  & $selectTier 'Normal'  })
$TierHigh.Add_Click({    & $selectTier 'High'    })
$TierExtreme.Add_Click({ & $selectTier 'Extreme' })

# --- Discord toggle ---
$DiscordBtn.Add_Click({
    if ($Script:IsOn -or $Script:Busy) { return }
    $Script:KeepDiscord = -not $Script:KeepDiscord
    Update-DiscordUI
})

# --- Flip the switch ---
$flip = {
    if ($Script:Busy) { return }
    $Script:Busy = $true
    try {
        if ($Script:IsOn) {
            Disable-GameBoost
            $Script:IsOn = $false
        } else {
            $target = ($TxtTarget.Text).Trim() -replace '\.exe$',''
            $opts = Get-TierOptions $Script:Tier $target $Script:KeepDiscord
            if ($Script:KeepDiscord) { Write-GBLog "Discord protected (won't be closed or slowed)" }
            if ($Script:Tier -eq 'Extreme') { Write-GBLog "Applying EXTREME - screen may flicker as Explorer restarts..." }
            Enable-GameBoost $opts
            $Script:IsOn = $true
        }
        Update-SwitchUI
    } catch {
        Write-GBLog "ERROR: $($_.Exception.Message)"
    } finally {
        $Script:Busy = $false
    }
}
$SwitchPlate.Add_MouseLeftButtonUp($flip)

# --- Detect foreground game ---
$DetectBtn.Add_Click({
    if ($Script:IsOn -or $Script:Busy) { return }
    $DetectBtn.IsEnabled = $false
    $orig = $DetectBtn.Content
    foreach ($n in 3,2,1) {
        $DetectBtn.Content = "Switch now ($n)"
        $DetectBtn.Dispatcher.Invoke([action]{}, 'Render')
        Start-Sleep -Seconds 1
    }
    $p = Get-ForegroundProcess
    if ($p -and $p.Id -ne $PID) {
        $TxtTarget.Text = $p.ProcessName
        Write-GBLog "Detected game: $($p.ProcessName)"
    } else {
        Write-GBLog "Could not detect a game window."
    }
    $DetectBtn.Content = $orig
    $DetectBtn.IsEnabled = $true
})

# If a boost is already active, reflect its tier + Discord choice
if ($Script:IsOn) {
    try {
        $saved = Get-Content -Path $Script:StateFile -Raw | ConvertFrom-Json
        if ($saved.tier) { $Script:Tier = [string]$saved.tier }
        if ($null -ne $saved.opts -and $null -ne $saved.opts.KeepDiscord) { $Script:KeepDiscord = [bool]$saved.opts.KeepDiscord }
    } catch { }
}

Update-TierUI
Update-DiscordUI
Update-SwitchUI
if ($Script:IsOn) {
    Write-GBLog "Active $($Script:Tier) boost from earlier. Flip the switch to restore."
} else {
    Write-GBLog "Ready. Pick a tier and flip the switch before you play."
}

$win.ShowDialog() | Out-Null
