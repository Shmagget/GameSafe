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

# The hard "NEVER kill" set for Deep Scan. Anything here is treated as essential
# and is excluded from the scan results entirely: Windows core/shell, security,
# GPU/audio drivers, anti-cheat, and the game LAUNCHERS (killing a launcher can
# close or break the game). The game itself and Discord are handled separately.
$Script:ScanProtect = @(
    # Windows core / shell / UWP hosts
    'system','idle','registry','smss','csrss','wininit','winlogon','services',
    'lsass','fontdrvhost','dwm','explorer','sihost','ctfmon','conhost','taskhostw',
    'runtimebroker','shellexperiencehost','startmenuexperiencehost','searchhost',
    'searchapp','searchindexer','textinputhost','applicationframehost','dllhost',
    'lockapp','logonui','useroobebroker','dashost','wmiprvse','svchost','spoolsv',
    'dwminit','wudfhost','backgroundtaskhost','smartscreen',
    # Security
    'msmpeng','nissrv','securityhealthservice','securityhealthsystray',
    # Audio / GPU / vendor drivers
    'audiodg','rtkauduservice64','realtek','nvcontainer','nvdisplay.container',
    'nvsphelper64','nvidia web helper','nvidia share','radeonsoftware','amdrsserv',
    'amdrssrcext','atieclxx','atiesrxx','igfxext','igfxem','igfxhk',
    # GameBoost itself / shells
    'powershell','pwsh','powershell_ise','windowsterminal','cmd',
    # Anti-cheat
    'easyanticheat','easyanticheat_eos','beservice','beclient','vgc','vgtray','vgk',
    'faceitclient','faceitservice',
    # Game launchers / platforms (the game may need these running)
    'steam','steamwebhelper','steamservice','epicgameslauncher','battle.net',
    'galaxyclient','origin','eadesktop','eabackgroundservice','uplay','upc',
    'riotclientservices','leagueclient','leagueclientux'
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

# ----------------------------------------------------------------------------
# Deep Scan: sample live CPU% + RAM for every process in our session, drop all
# essential ones (system, game, Discord-if-kept, anti-cheat, drivers, launchers)
# and return the non-essential resource users, grouped by name, sorted by usage.
# ----------------------------------------------------------------------------
function Get-ScanCandidates($opts) {
    $cores     = [Environment]::ProcessorCount
    $mySession = (Get-Process -Id $PID).SessionId
    $interval  = 0.6

    # First CPU-time snapshot
    $snap = @{}
    foreach ($p in Get-Process) { try { $snap[$p.Id] = $p.CPU } catch { } }
    Start-Sleep -Milliseconds ([int]($interval * 1000))

    $rows = @{}
    foreach ($p in Get-Process) {
        if ($p.SessionId -ne $mySession) { continue }   # skip session-0 services
        if ($p.Id -eq $PID) { continue }
        $n  = $p.ProcessName
        $nl = $n.ToLowerInvariant()
        if ($Script:ScanProtect  -contains $nl) { continue }
        if ($Script:ProtectNames -contains $nl) { continue }
        if (Test-KeepProcess $n $opts) { continue }      # game + Discord(if kept)

        $t1 = $snap[$p.Id]
        $t2 = $null; try { $t2 = $p.CPU } catch { }
        $cpu = 0.0
        if ($null -ne $t1 -and $null -ne $t2) { $cpu = (($t2 - $t1) / $interval / $cores) * 100 }
        if ($cpu -lt 0) { $cpu = 0 }
        $ram = 0; try { $ram = $p.WorkingSet64 } catch { }

        if (-not $rows.ContainsKey($nl)) {
            $rows[$nl] = [pscustomobject]@{ Name = $n; Count = 0; Cpu = 0.0; RamBytes = [int64]0 }
        }
        $rows[$nl].Count++
        $rows[$nl].Cpu      += $cpu
        $rows[$nl].RamBytes += [int64]$ram
    }

    # Keep only ones that actually use resources; attach MB + preselect flag
    $list = foreach ($r in $rows.Values) {
        $mb = [math]::Round($r.RamBytes / 1MB)
        if ($mb -lt 15 -and $r.Cpu -lt 0.5) { continue }   # hide trivia
        $r | Add-Member -NotePropertyName RamMB -NotePropertyValue $mb -Force
        $r | Add-Member -NotePropertyName CpuPct -NotePropertyValue ([math]::Round($r.Cpu,1)) -Force
        $r | Add-Member -NotePropertyName Preselect -NotePropertyValue ($mb -ge 100 -or $r.Cpu -ge 1.0) -Force
        $r
    }
    return @($list | Sort-Object -Property @{e='Cpu';Descending=$true}, @{e='RamBytes';Descending=$true})
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

    # --- Scanned non-essential processes (from Deep Scan) ---
    # Double-guarded: even if the queued list somehow contains something we
    # protect, the checks below stop it from being killed.
    if ($opts.ScanKill -and @($opts.ScanKill).Count -gt 0) {
        $sk = 0
        foreach ($name in $opts.ScanKill) {
            $nl = ([string]$name).ToLowerInvariant()
            if ($Script:ScanProtect -contains $nl) { continue }
            if ($Script:ProtectNames -contains $nl) { continue }
            foreach ($p in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                if ($p.Id -eq $PID) { continue }
                if (Test-KeepProcess $p.ProcessName $opts) { continue }
                try { Stop-Process -Id $p.Id -Force -ErrorAction Stop; $sk++ } catch { }
            }
        }
        Write-GBLog "Deep Scan: closed $sk extra non-essential process(es)"
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
        Title="GameBoost" Height="864" Width="470"
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

    <!-- Pre-flight: deep scan + game target -->
    <Border Grid.Row="5" Background="#161B22" CornerRadius="8" Padding="12" Margin="0,0,0,6">
      <StackPanel>
        <Grid>
          <Grid.ColumnDefinitions>
            <ColumnDefinition Width="*"/>
            <ColumnDefinition Width="Auto"/>
          </Grid.ColumnDefinitions>
          <StackPanel Grid.Column="0" VerticalAlignment="Center">
            <TextBlock Text="Deep scan" Foreground="#E6E6E6" FontWeight="Bold" FontSize="13"/>
            <TextBlock Name="ScanInfo" Foreground="#8B949E" FontSize="10.5" TextWrapping="Wrap"
                       Text="Find idle apps eating CPU/RAM and pick which to close."/>
          </StackPanel>
          <Button Name="ScanBtn" Grid.Column="1" Width="92" Height="34" Margin="8,0,0,0"
                  Background="#2D7D46" Foreground="White" FontWeight="Bold" Content="Scan now"/>
        </Grid>

        <Border Height="1" Background="#262C36" Margin="0,11,0,11"/>

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
$ScanBtn     = $win.FindName('ScanBtn')
$ScanInfo    = $win.FindName('ScanInfo')
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
$Script:ScanKill    = @()
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
    $ScanBtn.IsEnabled = $lock

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

# Modal Deep Scan review dialog. Returns an array of process names the user
# chose to close, or $null if they cancelled.
function Show-ScanDialog($scanOpts, $owner) {
    $candidates = Get-ScanCandidates $scanOpts

    [xml]$dx = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        Title="Deep scan" Height="560" Width="470" Background="#0E1117"
        WindowStartupLocation="CenterOwner" ResizeMode="CanResizeWithGrip">
  <Window.Resources>
    <Style TargetType="Button">
      <Setter Property="OverridesDefaultStyle" Value="True"/>
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
      </Style.Triggers>
    </Style>
  </Window.Resources>
  <Grid Margin="14">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="*"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>
    <TextBlock Grid.Row="0" Text="Non-essential apps using resources"
               Foreground="#E6E6E6" FontSize="15" FontWeight="Bold"/>
    <TextBlock Grid.Row="1" Name="ScanHdr" Foreground="#8B949E" FontSize="11"
               Margin="0,3,0,8" TextWrapping="Wrap"/>
    <Border Grid.Row="2" Background="#0A0D12" BorderBrush="#21262D" BorderThickness="1" CornerRadius="6">
      <ScrollViewer VerticalScrollBarVisibility="Auto" Padding="8">
        <StackPanel Name="ScanList"/>
      </ScrollViewer>
    </Border>
    <Grid Grid.Row="3" Margin="0,10,0,0">
      <Grid.ColumnDefinitions>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="Auto"/>
        <ColumnDefinition Width="*"/>
        <ColumnDefinition Width="Auto"/>
      </Grid.ColumnDefinitions>
      <Button Name="SelAll"  Grid.Column="0" Width="86" Height="32" Background="#21262D" Foreground="#C9D1D9" Content="Select all"/>
      <Button Name="SelNone" Grid.Column="1" Width="66" Height="32" Margin="6,0,0,0" Background="#21262D" Foreground="#C9D1D9" Content="None"/>
      <Button Name="UseBtn"  Grid.Column="3" Width="160" Height="32" Background="#2D7D46" Foreground="White" FontWeight="Bold" Content="Queue selected"/>
    </Grid>
  </Grid>
</Window>
"@
    $dr  = New-Object System.Xml.XmlNodeReader $dx
    $dlg = [Windows.Markup.XamlReader]::Load($dr)
    if ($owner) { $dlg.Owner = $owner }
    $ScanList = $dlg.FindName('ScanList')
    $ScanHdr  = $dlg.FindName('ScanHdr')
    $SelAll   = $dlg.FindName('SelAll')
    $SelNone  = $dlg.FindName('SelNone')
    $UseBtn   = $dlg.FindName('UseBtn')

    $warn = if (-not $scanOpts.Target) { " WARNING: no game is set, so a running game could appear below - leave it UNCHECKED." } else { '' }

    $checks = @()
    if ($candidates.Count -eq 0) {
        $ScanHdr.Text = "Nothing notable found - your background is already light. Flip the switch when ready."
        $UseBtn.Content = 'Close'
    } else {
        $preCount = @($candidates | Where-Object { $_.Preselect }).Count
        $ScanHdr.Text = "Found $($candidates.Count) app(s). The $preCount using the most CPU/RAM are pre-checked. Untick anything you want to keep - checked apps close when you flip the switch.$warn"
        foreach ($c in $candidates) {
            $cb = New-Object Windows.Controls.CheckBox
            $cb.Foreground = New-Brush '#C9D1D9'
            $cb.Margin     = '2,4,2,4'
            $cb.Tag        = $c.Name
            $cb.IsChecked  = [bool]$c.Preselect
            $extra = if ($c.Count -gt 1) { "  (x$($c.Count))" } else { '' }
            $cb.Content = ('{0}{1}   -   {2} MB   -   {3}% CPU' -f $c.Name, $extra, $c.RamMB, $c.CpuPct)
            $ScanList.Children.Add($cb) | Out-Null
            $checks += $cb
        }
    }

    $result = @{ names = $null }
    $SelAll.Add_Click({  foreach ($c in $checks) { $c.IsChecked = $true } })
    $SelNone.Add_Click({ foreach ($c in $checks) { $c.IsChecked = $false } })
    $UseBtn.Add_Click({
        $sel = @()
        foreach ($c in $checks) { if ($c.IsChecked) { $sel += ([string]$c.Tag).ToLowerInvariant() } }
        $result.names = $sel
        $dlg.DialogResult = $true
        $dlg.Close()
    }.GetNewClosure())

    $null = $dlg.ShowDialog()
    return $result.names
}

# --- Deep scan button ---
$ScanBtn.Add_Click({
    if ($Script:IsOn -or $Script:Busy) { return }
    $ScanBtn.IsEnabled = $false
    try {
        $target = ($TxtTarget.Text).Trim() -replace '\.exe$',''

        # A running game looks just like a resource hog to the scanner. If no game
        # is set, give the user 3s to focus it so we capture and exclude it.
        if (-not $target) {
            foreach ($n in 3,2,1) {
                $ScanInfo.Text = "Click your GAME now so it's never listed... ($n)"
                $ScanBtn.Dispatcher.Invoke([action]{}, 'Render')
                Start-Sleep -Seconds 1
            }
            $fg = Get-ForegroundProcess
            if ($fg -and $fg.Id -ne $PID) {
                $nl = $fg.ProcessName.ToLowerInvariant()
                if (($Script:ScanProtect -notcontains $nl) -and ($Script:ProtectNames -notcontains $nl)) {
                    $target = $fg.ProcessName
                    $TxtTarget.Text = $target
                    Write-GBLog "Game set to '$target' (excluded from scan)"
                }
            }
        }

        $ScanInfo.Text = 'Scanning processes...'
        $ScanBtn.Dispatcher.Invoke([action]{}, 'Render')
        $scanOpts = @{ Target = $target; KeepDiscord = $Script:KeepDiscord }
        $names = Show-ScanDialog $scanOpts $win
        if ($null -ne $names) {
            $Script:ScanKill = $names
            if ($names.Count -gt 0) {
                $ScanInfo.Text = "$($names.Count) app(s) queued - they close when you flip the switch."
                Write-GBLog "Deep Scan: armed $($names.Count) app(s) to close on flip"
            } else {
                $ScanInfo.Text = "Nothing queued. Scan again any time."
            }
        } else {
            $ScanInfo.Text = "Find idle apps eating CPU/RAM and pick which to close."
        }
    } catch {
        Write-GBLog "Scan error: $($_.Exception.Message)"
    } finally {
        $ScanBtn.IsEnabled = $true
    }
})

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
            $opts.ScanKill = $Script:ScanKill
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
