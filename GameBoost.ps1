#requires -version 5.1
<#
================================================================================
  GameBoost  -  Tiered one-switch game performance booster for Windows
================================================================================
  SPDX-License-Identifier: MIT
  License: MIT - free to use, modify, share, and adapt.

  Pick a tier, then flip the switch ON before you play:

    NORMAL  - Light touch. Game Mode on, capture off, and a safe game
              priority boost.
              Closes and stops nothing. Use when you just need a nudge.

    HIGH    - Adds AC-only performance power tuning, pauses indexing/capture
              services, and closes common bloat apps. Best for most people.

    EXTREME - Maximum. Everything in High PLUS:
                * Most aggressive temporary GameBoost power-plan tuning
                * Extended reversible service shutdown
                * Closes heavier apps including web browsers and Adobe helpers
                * Keeps the game on a safer AboveNormal priority
              Built for weak PCs without RAM trimming, broad priority lowering,
              or Explorer restarts that can make FPS worse.

  Flip OFF when done and GameBoost restores the saved power plan, services,
  registry values and touched process priorities. Apps it closes are recorded
  and relaunched on OFF when Windows exposes a usable executable path.

  SAFETY: Never touches critical Windows processes, never disables your
  antivirus, and never uses Realtime priority (which can freeze a PC).
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

# A second UI could otherwise overwrite an active recovery ledger. The mutex is
# released automatically if this process crashes.
$createdNew = $false
$Script:InstanceMutex = New-Object System.Threading.Mutex($true, 'Local\GameBoost.SingleInstance', [ref]$createdNew)
if (-not $createdNew) {
    [void][Windows.MessageBox]::Show('GameBoost is already open in this Windows session.', 'GameBoost')
    exit
}

# ============================================================================
# CONFIG  -  edit these lists to taste
# ============================================================================

# Services stopped at HIGH (and above). These can create measurable CPU/disk
# work. SysMain is deliberately left alone because disabling caching can
# increase game stutter.
$Script:SvcLight = @(
    'WSearch'           # Windows Search indexer (disk + CPU spikes)
    'DiagTrack'         # Connected User Experiences and Telemetry
    'BcastDVRUserService_*' # Game DVR broadcast/capture service
)

# Added at HIGH (and above).
$Script:SvcStandard = @(
    'MapsBroker'        # Downloaded Maps Manager
    'WerSvc'            # Windows Error Reporting
)

# Added at EXTREME only. The update stack is skipped when servicing is active.
$Script:SvcExtended = @(
    'wuauserv'          # Windows Update
    'BITS'              # Background Intelligent Transfer
    'DoSvc'             # Delivery Optimization
    'dmwappushservice'  # WAP push routing (telemetry)
)
$Script:UpdateServiceNames = @('wuauserv','bits','dosvc')

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
    'Copilot'
    'MicrosoftStartFeedProvider'
    'GameBarFTServer'
)

# Additionally closed at EXTREME. Heavier apps incl. browsers - big RAM wins.
$Script:BloatExtended = @(
    'Discord'
    'msedge','chrome','firefox','brave','opera','vivaldi'
    'GameBar','XboxGameBar','GameBarFTServer'
    'AdobeIPCBroker','CCXProcess','Acrobat','AdobeCollabSync'
    'GoogleCrashHandler','GoogleCrashHandler64','GoogleUpdate'
)

# Processes protected from Deep Scan cleanup and any future priority experiments.
# Critical UI, audio, and anti-cheat should stay untouched.
$Script:ProtectNames = @(
    'explorer','dwm','audiodg','csrss','wininit','winlogon','services','lsass',
    'smss','svchost','system','idle','registry','conhost','fontdrvhost',
    'powershell','pwsh','sihost','ctfmon','SystemSettings',
    'EasyAntiCheat','EasyAntiCheat_EOS','BEService','vgc','vgtray','vgk',
    'SteamService','obs32','obs64','Streamlabs OBS','voicemeeter','voicemeeter8'
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

$Script:StateDir  = Join-Path $env:LOCALAPPDATA 'GameBoost'
$Script:StateFile = Join-Path $Script:StateDir 'state.json'

# Power plan sub-settings tuned only inside the temporary GameBoost plan.
$Script:PowerGuids = @{
    SUB_PROCESSOR  = '54533251-82be-4824-96c1-47b60b740d00'
    PROCTHROTTLEMAX= 'bc5038f7-23e0-4960-96da-33abaf5935ec'
    PERFEPP        = '36687f9e-e3a5-4dbf-b1dc-15eb381c6863'
}

# ----------------------------------------------------------------------------
# Win32 helper: foreground window detection
# ----------------------------------------------------------------------------
if (-not ([System.Management.Automation.PSTypeName]'GBNative').Type) {
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class GBNative {
    [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
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

function Test-GBPowerSchemeExists([string]$guid) {
    if (-not $guid) { return $false }
    $out = powercfg /list 2>$null | Out-String
    return ($out -match [regex]::Escape($guid))
}

function Get-GBProcessPathByName([string]$name) {
    if (-not $name) { return $null }
    foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
        try {
            if ($p.Path -and (Test-Path -LiteralPath $p.Path)) { return [string]$p.Path }
        } catch { }
        try {
            $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($p.Id)" -ErrorAction Stop
            if ($cim.ExecutablePath -and (Test-Path -LiteralPath $cim.ExecutablePath)) { return [string]$cim.ExecutablePath }
        } catch { }
    }
    return $null
}

function Save-GBState($state) {
    if (-not (Test-Path $Script:StateDir)) {
        New-Item -ItemType Directory -Path $Script:StateDir -Force | Out-Null
    }
    $tempFile = "$($Script:StateFile).tmp"
    $backupFile = "$($Script:StateFile).bak"
    $json = $state | ConvertTo-Json -Depth 8
    [IO.File]::WriteAllText($tempFile, $json, (New-Object Text.UTF8Encoding($false)))
    if (Test-Path $Script:StateFile) {
        [IO.File]::Replace($tempFile, $Script:StateFile, $backupFile)
        Remove-Item -LiteralPath $backupFile -Force -ErrorAction SilentlyContinue
    }
    else { [IO.File]::Move($tempFile, $Script:StateFile) }
}

function Test-GBStateProperty($state, [string]$name) {
    if ($state -is [System.Collections.IDictionary]) { return $state.Contains($name) }
    return @($state.PSObject.Properties.Name) -contains $name
}

function Set-GBStateProperty($state, [string]$name, $value) {
    if ($state -is [System.Collections.IDictionary]) { $state[$name] = $value; return }
    if (Test-GBStateProperty $state $name) { $state.$name = $value }
    else { $state | Add-Member -NotePropertyName $name -NotePropertyValue $value -Force }
}

function Test-GBOnBattery {
    try {
        $batt = @(Get-CimInstance Win32_Battery -ErrorAction Stop)
        return ($batt.Count -gt 0 -and @($batt | Where-Object { $_.BatteryStatus -eq 1 }).Count -gt 0)
    } catch { return $false }
}

function Get-GBStartIso($process) {
    try { return $process.StartTime.ToUniversalTime().ToString('o') } catch { return $null }
}

function Add-GBPriorityRecord($state, $process) {
    if (-not (Test-GBStateProperty $state 'priorityChanges')) { Set-GBStateProperty $state 'priorityChanges' ([object[]]@()) }
    $startIso = Get-GBStartIso $process
    foreach ($r in @($state.priorityChanges)) {
        if ([int]$r.id -eq [int]$process.Id -and [string]$r.startTime -eq [string]$startIso) { return $r }
    }
    $oldPriority = $null
    try { $oldPriority = [string]$process.PriorityClass } catch { return }
    $record = @{
        id = [int]$process.Id
        name = [string]$process.ProcessName
        startTime = $startIso
        priority = $oldPriority
    }
    $state.priorityChanges += $record
    Save-GBState $state
    return $record
}

function Set-GBProcessPriority($state, $process, [string]$priority) {
    $record = Add-GBPriorityRecord $state $process
    if (-not $record) { return $false }
    try {
        if ([string]$process.PriorityClass -ne $priority) {
            $process.PriorityClass = $priority
        }
        Set-GBStateProperty $record 'appliedPriority' $priority
        Save-GBState $state
        return $true
    } catch { return $false }
}

function Restore-GBPriorities($state) {
    if (-not $state.priorityChanges) { return $true }
    $restored = 0
    $restoreOk = $true
    foreach ($r in @($state.priorityChanges)) {
        try {
            $p = Get-Process -Id ([int]$r.id) -ErrorAction Stop
        } catch { continue }
        try {
            if ($p.ProcessName -ne [string]$r.name) { continue }
            $startIso = Get-GBStartIso $p
            if ($r.startTime -and $startIso -and ([string]$r.startTime -ne [string]$startIso)) { continue }
            if ((Test-GBStateProperty $r 'appliedPriority') -and [string]$p.PriorityClass -ne [string]$r.appliedPriority) {
                Write-GBLog "Preserved newer priority change: $($p.ProcessName)"
                continue
            }
            $p.PriorityClass = [string]$r.priority
            $restored++
        } catch { $restoreOk = $false }
    }
    Write-GBLog "Restored priority of $restored touched process(es)"
    return $restoreOk
}

function Get-GBClosedAppRecord($process, [string]$reason) {
    $path = $null
    $cmd  = $null
    $workingSetMB = 0
    try { $path = $process.Path } catch { }
    try { $workingSetMB = [math]::Round(([double]$process.WorkingSet64 / 1MB), 1) } catch { }
    try {
        $cim = Get-CimInstance Win32_Process -Filter "ProcessId=$($process.Id)" -ErrorAction Stop
        if (-not $path -and $cim.ExecutablePath) { $path = [string]$cim.ExecutablePath }
        if ($cim.CommandLine) { $cmd = [string]$cim.CommandLine }
    } catch { }

    return @{
        id = [int]$process.Id
        name = [string]$process.ProcessName
        path = $path
        commandLine = $cmd
        startTime = (Get-GBStartIso $process)
        workingSetMB = $workingSetMB
        reason = $reason
    }
}

function Add-GBClosedAppRecord($state, $record) {
    if (-not (Test-GBStateProperty $state 'closedApps')) { Set-GBStateProperty $state 'closedApps' ([object[]]@()) }
    foreach ($r in @($state.closedApps)) {
        if ([int]$r.id -eq [int]$record.id -and [string]$r.startTime -eq [string]$record.startTime) { return }
    }
    $state.closedApps += $record
    Save-GBState $state
}

function Stop-GBTrackedProcess($state, $process, $opts, [string]$reason) {
    if ($process.Id -eq $PID) { return $false }
    if (Test-KeepProcess $process.ProcessName $opts) { return $false }
    $record = Get-GBClosedAppRecord $process $reason
    if (-not $record.path -or -not (Test-Path -LiteralPath $record.path)) {
        Write-GBLog "  (left $($process.ProcessName) running: no reliable relaunch path)"
        return $false
    }
    # Persist intent first. If GameBoost itself closes after Stop-Process, OFF
    # still knows what must be relaunched. A still-running app is skipped later.
    Add-GBClosedAppRecord $state $record
    try {
        $hasWindow = $false
        try { $hasWindow = ($process.MainWindowHandle -ne [IntPtr]::Zero) } catch { }
        if ($hasWindow) {
            if (-not $process.CloseMainWindow() -or -not $process.WaitForExit(3000)) {
                throw "The app did not accept a normal close request"
            }
        } else {
            Stop-Process -Id $process.Id -Force -ErrorAction Stop
        }
        return $true
    } catch {
        $state.closedApps = @($state.closedApps | Where-Object {
            -not ([int]$_.id -eq [int]$record.id -and [string]$_.startTime -eq [string]$record.startTime)
        })
        Save-GBState $state
        return $false
    }
}

function Get-GBLaunchArguments([string]$commandLine, [string]$path) {
    if (-not $commandLine -or -not $path) { return $null }
    $cmd = $commandLine.Trim()
    $quotedPath = '"' + $path + '"'
    if ($cmd.StartsWith($quotedPath, [StringComparison]::OrdinalIgnoreCase)) {
        return $cmd.Substring($quotedPath.Length).Trim()
    }
    if ($cmd.StartsWith($path, [StringComparison]::OrdinalIgnoreCase)) {
        return $cmd.Substring($path.Length).Trim()
    }
    return $null
}

function Restore-GBClosedApps($state) {
    if (-not $state.closedApps) { return $true }
    $seen = @{}
    $relaunched = 0
    $restoreOk = $true
    foreach ($r in @($state.closedApps)) {
        $path = [string]$r.path
        $name = [string]$r.name
        if (-not $path -or -not (Test-Path -LiteralPath $path)) {
            Write-GBLog "  (cannot relaunch ${name}: executable path is unavailable)"
            continue
        }
        $key = $path.ToLowerInvariant()
        $alreadyRunning = $false
        foreach ($p in @(Get-Process -Name $name -ErrorAction SilentlyContinue)) {
            $runningPath = $null; try { $runningPath = [string]$p.Path } catch { }
            if ($runningPath -and $runningPath.ToLowerInvariant() -eq $key) { $alreadyRunning = $true; break }
        }
        if ($alreadyRunning) { continue }
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        # Multi-process browsers and Electron apps record several rows. Prefer
        # the shortest non-renderer command line so one normal parent process
        # recreates its own helpers.
        $launchRecord = @($state.closedApps | Where-Object {
            [string]$_.path -and ([string]$_.path).ToLowerInvariant() -eq $key
        } | Sort-Object `
            @{ Expression = { if ([string]$_.commandLine -match '(?i)--type=|--utility-sub-type=') { 1 } else { 0 } } }, `
            @{ Expression = { ([string]$_.commandLine).Length } } | Select-Object -First 1)
        $arguments = Get-GBLaunchArguments ([string]$launchRecord.commandLine) $path
        try {
            $startArgs = @{ FilePath = $path; WorkingDirectory = (Split-Path -Parent $path); ErrorAction = 'Stop' }
            if ($arguments) { $startArgs.ArgumentList = $arguments }
            Start-Process @startArgs
            $relaunched++
        } catch {
            try {
                Start-Process -FilePath explorer.exe -ArgumentList "`"$path`"" -ErrorAction Stop
                $relaunched++
            } catch {
                $restoreOk = $false
                Write-GBLog "  (could not relaunch $name; OFF can retry)"
            }
        }
    }
    Write-GBLog "Relaunched $relaunched app(s) GameBoost had closed"
    return $restoreOk
}

function Backup-GBRegValue($state, [string]$path, [string]$name) {
    if (-not (Test-GBStateProperty $state 'registry')) { Set-GBStateProperty $state 'registry' ([object[]]@()) }
    foreach ($r in @($state.registry)) {
        if ([string]$r.path -eq $path -and [string]$r.name -eq $name) { return $r }
    }

    $exists = $false
    $value  = $null
    $kind   = $null
    $keyExisted = Test-Path $path
    if ($keyExisted) {
        try {
            $item = Get-ItemProperty -Path $path -Name $name -ErrorAction Stop
            $value = $item.$name
            $exists = $true
            try { $kind = [string](Get-Item -Path $path).GetValueKind($name) } catch { $kind = $null }
        } catch { }
    }

    $record = @{
        path = $path
        name = $name
        keyExisted = $keyExisted
        existed = $exists
        value = $value
        kind = $kind
    }
    $state.registry += $record
    Save-GBState $state
    return $record
}

function Set-GBRegValue($state, [string]$path, [string]$name, $value, [string]$kind) {
    $record = Backup-GBRegValue $state $path $name
    if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
    try {
        Set-ItemProperty -Path $path -Name $name -Value $value -Type $kind -Force -ErrorAction Stop
        $record.appliedValue = $value
        $record.appliedKind = $kind
        Save-GBState $state
        return $true
    } catch {
        Write-GBLog "  (registry tweak skipped: $name)"
        return $false
    }
}

function Restore-GBRegistry($state) {
    if (-not $state.registry) { return $true }
    $restored = 0
    $restoreOk = $true
    foreach ($r in @($state.registry)) {
        $path = [string]$r.path
        $name = [string]$r.name
        try {
            # Do not overwrite a value the user or Windows changed while boost
            # was active. Legacy ledgers without appliedValue still restore.
            if (Test-GBStateProperty $r 'appliedValue') {
                $currentExists = $false
                $currentValue = $null
                if (Test-Path $path) {
                    $key = Get-Item -Path $path -ErrorAction Stop
                    if (@($key.GetValueNames()) -contains $name) {
                        $currentExists = $true
                        $currentValue = $key.GetValue($name, $null, [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                    }
                }
                if (-not $currentExists -or [string]$currentValue -ne [string]$r.appliedValue) {
                    Write-GBLog "Preserved newer registry change: $name"
                    continue
                }
            }
            if ([bool]$r.existed) {
                if (-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                $kind = if ($r.kind) { [string]$r.kind } else { 'String' }
                Set-ItemProperty -Path $path -Name $name -Value $r.value -Type $kind -Force -ErrorAction Stop
            } else {
                if (Test-Path $path) {
                    $restoreKey = Get-Item -Path $path -ErrorAction Stop
                    if (@($restoreKey.GetValueNames()) -contains $name) {
                        Remove-ItemProperty -Path $path -Name $name -ErrorAction Stop
                    }
                }
                if ((Test-GBStateProperty $r 'keyExisted') -and -not [bool]$r.keyExisted -and (Test-Path $path)) {
                    try {
                        $key = Get-Item -Path $path -ErrorAction Stop
                        if ($key.GetValueNames().Count -eq 0 -and $key.GetSubKeyNames().Count -eq 0) {
                            Remove-Item -Path $path -Force -ErrorAction Stop
                        }
                    } catch { }
                }
            }
            $restored++
        } catch { $restoreOk = $false }
    }
    Write-GBLog "Restored $restored registry setting(s)"
    return $restoreOk
}

function New-GBPowerPlan([string]$baseGuid, [string]$tier) {
    $out = powercfg -duplicatescheme $baseGuid 2>$null | Out-String
    if ($out -match '([0-9a-fA-F-]{36})') {
        $newGuid = $Matches[1]
        powercfg -changename $newGuid "GameBoost $tier" "Temporary GameBoost gaming plan - removed when boost is turned off" 2>$null
        return $newGuid
    }
    return $null
}

function Apply-GBPowerTweaks([string]$scheme, [string]$tier) {
    $g = $Script:PowerGuids
    # AC-only and deliberately narrow. OEM battery, thermal, storage, PCIe,
    # USB, Wi-Fi, boost-mode, and minimum-processor policies are preserved.
    $eppAc = if ($tier -eq 'Extreme') { 0 } else { 15 }
    powercfg /setacvalueindex $scheme $g.SUB_PROCESSOR $g.PROCTHROTTLEMAX 100 2>$null | Out-Null
    powercfg /setacvalueindex $scheme $g.SUB_PROCESSOR $g.PERFEPP $eppAc 2>$null | Out-Null
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

function Get-TierOptions([string]$tier, [string]$target, [bool]$keepDiscord, [string]$targetPath) {
    $o = @{
        Tier = $tier; Target = $target; TargetPath = $targetPath; KeepDiscord = $keepDiscord
        PowerMode = 'none'; ServiceLevel = 'none'; Bloat = 'none'
        Dvr = $false; Priority = $false
    }
    switch ($tier) {
        'Normal' {
            $o.Dvr = $true; $o.Priority = $true
        }
        'High' {
            $o.PowerMode = 'adaptive'; $o.ServiceLevel = 'standard'; $o.Bloat = 'standard'
            $o.Dvr = $true; $o.Priority = $true
        }
        'Extreme' {
            $o.PowerMode = 'adaptive'; $o.ServiceLevel = 'extended'; $o.Bloat = 'extended'
            $o.Dvr = $true; $o.Priority = $true
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

function Test-GBWindowsServicingActive {
    foreach ($name in @('TiWorker','TrustedInstaller','MoUsoCoreWorker','poqexec','dismhost')) {
        if (Get-Process -Name $name -ErrorAction SilentlyContinue) { return $true }
    }
    return $false
}

function Get-GBRunningDependentNames($service) {
    $result = @()
    $seen = @{}
    $queue = @($service.DependentServices)
    while ($queue.Count -gt 0) {
        $current = $queue[0]
        if ($queue.Count -gt 1) { $queue = @($queue[1..($queue.Count - 1)]) } else { $queue = @() }
        if (-not $current -or $seen.ContainsKey($current.Name)) { continue }
        $seen[$current.Name] = $true
        if ($current.Status -eq 'Running') { $result += $current.Name }
        try { $queue += @($current.DependentServices) } catch { }
    }
    return @($result)
}

# ----------------------------------------------------------------------------
# Deep Scan: sample live CPU%, RAM, and disk I/O for every process in our
# session, drop all essential ones (system, game, Discord-if-kept, anti-cheat,
# drivers, launchers) and return the non-essential resource users, grouped by
# name, sorted by usage.
# ----------------------------------------------------------------------------
function Get-ScanCandidates($opts) {
    $cores     = [Environment]::ProcessorCount
    $mySession = (Get-Process -Id $PID).SessionId

    # First CPU-time snapshot
    $snap = @{}
    foreach ($p in Get-Process) { try { $snap[$p.Id] = $p.CPU } catch { } }
    $sampleWatch = [Diagnostics.Stopwatch]::StartNew()
    Start-Sleep -Milliseconds 1500

    $ioById = @{}
    try {
        foreach ($perf in Get-CimInstance Win32_PerfFormattedData_PerfProc_Process -ErrorAction Stop) {
            if ($perf.IDProcess -gt 0) { $ioById[[int]$perf.IDProcess] = [int64]$perf.IODataBytesPersec }
        }
    } catch { }
    $sampleWatch.Stop()
    $interval = [math]::Max(0.1, $sampleWatch.Elapsed.TotalSeconds)

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
        $disk = 0; if ($ioById.ContainsKey($p.Id)) { $disk = [int64]$ioById[$p.Id] }
        $procPath = $null; try { $procPath = [string]$p.Path } catch { }

        if (-not $rows.ContainsKey($nl)) {
            $rows[$nl] = [pscustomobject]@{
                Name = $n; Count = 0; Cpu = 0.0; RamBytes = [int64]0; DiskBytes = [int64]0
                HasWindow = $false; Path = $procPath; PathConflict = $false
            }
        }
        if ($procPath -and $rows[$nl].Path -and $procPath -ine [string]$rows[$nl].Path) { $rows[$nl].PathConflict = $true }
        elseif ($procPath -and -not $rows[$nl].Path) { $rows[$nl].Path = $procPath }
        $rows[$nl].Count++
        $rows[$nl].Cpu      += $cpu
        $rows[$nl].RamBytes += [int64]$ram
        $rows[$nl].DiskBytes += [int64]$disk
        try { if ($p.MainWindowHandle -ne [IntPtr]::Zero) { $rows[$nl].HasWindow = $true } } catch { }
    }

    # Keep only ones that actually use resources; attach MB, MB/s + preselect flag
    $list = foreach ($r in $rows.Values) {
        $mb = [math]::Round($r.RamBytes / 1MB)
        $diskMbps = [math]::Round($r.DiskBytes / 1MB, 1)
        if ($mb -lt 15 -and $r.Cpu -lt 0.5 -and $diskMbps -lt 0.2) { continue }   # hide trivia
        $r | Add-Member -NotePropertyName RamMB -NotePropertyValue $mb -Force
        $r | Add-Member -NotePropertyName CpuPct -NotePropertyValue ([math]::Round($r.Cpu,1)) -Force
        $r | Add-Member -NotePropertyName DiskMBps -NotePropertyValue $diskMbps -Force
        # Memory occupancy alone does not mean an app is stealing frame time.
        $heavy = ($r.Cpu -ge 2.0 -or $diskMbps -ge 1.0)
        $reliablePath = ([string]$r.Path -and -not $r.PathConflict)
        $r | Add-Member -NotePropertyName Preselect -NotePropertyValue ($heavy -and -not $r.HasWindow -and $reliablePath) -Force
        $r
    }
    return @($list | Sort-Object -Property @{e='Cpu';Descending=$true}, @{e='DiskBytes';Descending=$true}, @{e='RamBytes';Descending=$true})
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
        phase     = 'enabling'
        tier      = $opts.Tier
        target    = $opts.Target
        targetPath = $opts.TargetPath
        opts      = $opts
        prevPowerScheme = $null
        powerPlanCreated = $null
        powerPlanBase    = $null
        services  = @()
        registry  = @()
        priorityChanges = @()
        closedApps = @()
    }
    Save-GBState $state
    if (Test-GBOnBattery) {
        Write-GBLog "Laptop appears to be on battery - plug in for best FPS and less throttling."
    }

    # --- Power plan ---
    if ($opts.PowerMode -ne 'none') {
        $state.prevPowerScheme = Get-ActiveSchemeGuid
        # Clone the user's active plan so OEM thermal/fan behavior is retained,
        # then tune only the temporary copy.
        $baseGuid = $state.prevPowerScheme
        $state.powerPlanBase = $baseGuid
        Save-GBState $state

        $gbPlan = if ($baseGuid) { New-GBPowerPlan $baseGuid $opts.Tier } else { $null }
        if ($gbPlan) {
            $state.powerPlanCreated = $gbPlan
            Save-GBState $state
            Apply-GBPowerTweaks $gbPlan $opts.Tier
            powercfg /setactive $gbPlan 2>$null
            if ((Get-ActiveSchemeGuid) -ieq $gbPlan) {
                Write-GBLog "Power plan -> temporary GameBoost $($opts.Tier) plan"
            } else {
                Write-GBLog "Temporary plan could not be activated; existing plan remains active"
            }
        } else {
            Write-GBLog "Could not create a temporary plan; existing plan remains active"
        }
    }

    # --- Services ---
    $svcSet = Get-ServiceSet $opts.ServiceLevel
    if ($svcSet.Count -gt 0) {
        $stopped = 0
        $serviceSeen = @{}
        $servicingActive = Test-GBWindowsServicingActive
        if ($servicingActive -and $opts.ServiceLevel -eq 'extended') {
            Write-GBLog "Windows servicing is active - update services will be left running"
        }
        foreach ($pattern in $svcSet) {
            foreach ($svc in @(Get-Service -Name $pattern -ErrorAction SilentlyContinue)) {
                if ($serviceSeen.ContainsKey($svc.Name)) { continue }
                if ($servicingActive -and $Script:UpdateServiceNames -contains $svc.Name.ToLowerInvariant()) { continue }
                $serviceSeen[$svc.Name] = $true
                $wasRunning = ($svc.Status -eq 'Running')
                $deps = @()
                try { $deps = @(Get-GBRunningDependentNames $svc) } catch { }
                $serviceRecord = @{
                    name = $svc.Name; wasRunning = $wasRunning
                    stopAttempted = $false; stopSucceeded = $false; dependents = $deps
                }
                $state.services += $serviceRecord
                Save-GBState $state
                if ($wasRunning) {
                    try {
                        $serviceRecord.stopAttempted = $true
                        Save-GBState $state
                        Stop-Service -Name $svc.Name -Force -ErrorAction Stop
                        $serviceRecord.stopSucceeded = $true
                        Save-GBState $state
                        $stopped++
                    }
                    catch { Write-GBLog "  (could not stop $($svc.Name))" }
                }
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
                if (Stop-GBTrackedProcess $state $p $opts 'tier-bloat') { $killed++ }
            }
        }
        Write-GBLog "Closed $killed background app process(es)"
    }

    # --- Scanned non-essential processes (from Deep Scan) ---
    # Double-guarded: even if the queued list somehow contains something we
    # protect, the checks below stop it from being killed.
    if ($opts.ScanKill -and @($opts.ScanKill).Count -gt 0) {
        $sk = 0
        foreach ($entry in $opts.ScanKill) {
            $name = if ($entry -is [string]) { [string]$entry } else { [string]$entry.Name }
            $expectedPath = if ($entry -is [string]) { $null } else { [string]$entry.Path }
            if (-not $name) { continue }
            $nl = ([string]$name).ToLowerInvariant()
            if ($Script:ScanProtect -contains $nl) { continue }
            if ($Script:ProtectNames -contains $nl) { continue }
            foreach ($p in (Get-Process -Name $name -ErrorAction SilentlyContinue)) {
                if ($expectedPath) {
                    $actualPath = $null; try { $actualPath = [string]$p.Path } catch { }
                    if (-not $actualPath -or $actualPath -ine $expectedPath) { continue }
                }
                if (Stop-GBTrackedProcess $state $p $opts 'deep-scan') { $sk++ }
            }
        }
        Write-GBLog "Deep Scan: closed $sk extra non-essential process(es)"
    }

    # --- Game DVR off ---
    if ($opts.Dvr) {
        $p1 = 'HKCU:\System\GameConfigStore'
        $p2 = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
        $p3 = 'HKCU:\SOFTWARE\Microsoft\GameBar'
        [void](Set-GBRegValue $state $p1 'GameDVR_Enabled' 0 'DWord')
        [void](Set-GBRegValue $state $p2 'AppCaptureEnabled' 0 'DWord')
        [void](Set-GBRegValue $state $p2 'HistoricalCaptureEnabled' 0 'DWord')
        [void](Set-GBRegValue $state $p3 'AllowAutoGameMode' 1 'DWord')
        [void](Set-GBRegValue $state $p3 'AutoGameModeEnabled' 1 'DWord')
        Write-GBLog "Game Mode on and background capture off"
    }

    # --- Game priority ---
    if ($opts.Priority -and $opts.Target) {
        $n = 0
        foreach ($p in (Get-Process -Name $opts.Target -ErrorAction SilentlyContinue)) {
            if (Set-GBProcessPriority $state $p 'AboveNormal') { $n++ }
        }
        if ($n -gt 0) { Write-GBLog "Game '$($opts.Target)' priority -> AboveNormal ($n proc)" }
        else { Write-GBLog "Game '$($opts.Target)' not running yet (watcher will boost it while this window is open)" }
    } elseif ($opts.Priority) {
        Write-GBLog "No game process selected - priority boost skipped"
    }

    $releasedMB = [math]::Round((@($state.closedApps) | Measure-Object -Property workingSetMB -Sum).Sum, 0)
    if ($releasedMB -gt 0) { Write-GBLog "Closed apps had about $releasedMB MB of active memory" }

    $state.phase = 'active'
    Save-GBState $state
    Write-GBLog "=== BOOST ON ($($opts.Tier)) ==="
}

# ============================================================================
# DISABLE  -  restore tracked state
# ============================================================================
function Disable-GameBoost {
    if (-not (Test-Path $Script:StateFile)) {
        Write-GBLog "No saved state - nothing to restore."
        return $true
    }
    $state = Get-Content -Path $Script:StateFile -Raw | ConvertFrom-Json
    $restoreOk = $true

    # --- Power plan ---
    if ($state.prevPowerScheme) {
        powercfg /setactive $state.prevPowerScheme 2>$null
        if ((Get-ActiveSchemeGuid) -ieq [string]$state.prevPowerScheme) {
            Write-GBLog "Power plan restored"
        } else {
            $restoreOk = $false
            Write-GBLog "  (power plan restore needs another try)"
        }
    }
    if ($state.powerPlanCreated -and (Test-GBPowerSchemeExists ([string]$state.powerPlanCreated))) {
        try {
            powercfg /delete $state.powerPlanCreated 2>$null | Out-Null
            if (Test-GBPowerSchemeExists ([string]$state.powerPlanCreated)) { throw 'power plan still exists' }
            Write-GBLog "Temporary GameBoost power plan removed"
        } catch {
            $restoreOk = $false
            Write-GBLog "  (temporary power plan removal needs another try)"
        }
    }

    # --- Services ---
    if ($state.services) {
        $started = 0
        $startedNames = @{}
        foreach ($s in $state.services) {
            $stopWasAttempted = (-not (Test-GBStateProperty $s 'stopAttempted')) -or [bool]$s.stopAttempted
            if ($s.wasRunning -and $stopWasAttempted -and -not $startedNames.ContainsKey([string]$s.name)) {
                $serviceName = [string]$s.name
                try {
                    $service = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
                    if ($service -and $service.Status -ne 'Running') { Start-Service -Name $serviceName -ErrorAction Stop }
                    $startedNames[[string]$s.name] = $true
                    $started++
                } catch {
                    $restoreOk = $false
                    Write-GBLog "  (could not restart $serviceName; OFF can retry)"
                }
            }
            if (-not $stopWasAttempted) { continue }
            foreach ($d in @($s.dependents)) {
                if (-not $d -or $startedNames.ContainsKey([string]$d)) { continue }
                try {
                    $dependent = Get-Service -Name $d -ErrorAction SilentlyContinue
                    if ($dependent -and $dependent.Status -ne 'Running') { Start-Service -Name $d -ErrorAction Stop }
                    $startedNames[[string]$d] = $true
                    $started++
                } catch {
                    $restoreOk = $false
                    Write-GBLog "  (could not restart $d; OFF can retry)"
                }
            }
        }
        Write-GBLog "Restarted $started service(s)"
    }

    if (-not [bool](Restore-GBRegistry $state)) { $restoreOk = $false }
    if (-not [bool](Restore-GBPriorities $state)) { $restoreOk = $false }
    if (-not [bool](Restore-GBClosedApps $state)) { $restoreOk = $false }

    if ($restoreOk) {
        Remove-Item -Path $Script:StateFile -Force -ErrorAction SilentlyContinue
        Write-GBLog "=== BOOST OFF - tracked settings restored ==="
        return $true
    }

    Write-GBLog "Restore is incomplete. The recovery state was kept; flip OFF again to retry."
    return $false
}

# ============================================================================
# GUI
# ============================================================================
[xml]$xaml = @"
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
        xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
        Title="GameBoost" Height="884" Width="470"
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
               Text="reversible - admin" Foreground="#5A6472" FontSize="11"/>

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
      <TextBlock Name="TierDesc" Foreground="#8B949E" FontSize="11.5" TextWrapping="Wrap" Height="66"/>
    </Border>

    <!-- THE LIGHT SWITCH -->
    <Border Grid.Row="3" Name="SwitchPlate" Width="166" Height="252" Margin="0,6,0,12"
            CornerRadius="14" Background="#E9E0D1" BorderBrush="#B8AA91" BorderThickness="2"
            Cursor="Hand" HorizontalAlignment="Center">
      <Canvas Width="166" Height="252" ClipToBounds="False">
        <Canvas.Background>
          <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
            <GradientStop Color="#FFF8EA" Offset="0"/>
            <GradientStop Color="#E7D8BF" Offset="1"/>
          </LinearGradientBrush>
        </Canvas.Background>
        <!-- mounting screws -->
        <Ellipse Canvas.Left="76.5" Canvas.Top="14" Width="13" Height="13" Fill="#D3C4A8"
                 Stroke="#9B8C72" StrokeThickness="1"/>
        <Rectangle Canvas.Left="79" Canvas.Top="20" Width="8" Height="1.4" Fill="#8B7C64"
                   RenderTransformOrigin="0.5,0.5">
          <Rectangle.RenderTransform><RotateTransform Angle="-18"/></Rectangle.RenderTransform>
        </Rectangle>
        <Ellipse Canvas.Left="76.5" Canvas.Top="225" Width="13" Height="13" Fill="#D3C4A8"
                 Stroke="#9B8C72" StrokeThickness="1"/>
        <Rectangle Canvas.Left="79" Canvas.Top="231" Width="8" Height="1.4" Fill="#8B7C64"
                   RenderTransformOrigin="0.5,0.5">
          <Rectangle.RenderTransform><RotateTransform Angle="16"/></Rectangle.RenderTransform>
        </Rectangle>
        <!-- engraved ON / OFF -->
        <TextBlock Name="LblOn" Canvas.Left="71" Canvas.Top="39" Text="ON"
                   Foreground="#9A8D77" FontWeight="Bold" FontSize="12"/>
        <TextBlock Name="LblOff" Canvas.Left="69" Canvas.Top="202" Text="OFF"
                   Foreground="#766B59" FontWeight="Bold" FontSize="12"/>
        <!-- small pilot light keeps the tier color visible without making the switch look digital -->
        <Ellipse Name="Led" Canvas.Left="121" Canvas.Top="43" Width="10" Height="10"
                 Fill="#AFA187" Stroke="#8B7C64" StrokeThickness="1"/>

        <Border Canvas.Left="44" Canvas.Top="62" Width="78" Height="142" CornerRadius="10"
                Background="#C8B89B" BorderBrush="#9D8D72" BorderThickness="1">
          <Border.Effect>
            <DropShadowEffect Color="#6A5D49" BlurRadius="8" ShadowDepth="2" Opacity="0.28"/>
          </Border.Effect>
        </Border>

        <Border Name="Lever" Canvas.Left="57" Canvas.Top="82" Width="52" Height="112"
                CornerRadius="6" Background="#F8F0E2" BorderBrush="#B7A78A"
                BorderThickness="1.2">
          <Border.Effect>
            <DropShadowEffect Color="#4D4030" BlurRadius="11" ShadowDepth="4" Opacity="0.45"/>
          </Border.Effect>
          <Grid>
            <Grid.Background>
              <LinearGradientBrush StartPoint="0,0" EndPoint="1,1">
                <GradientStop Color="#FFFDF7" Offset="0"/>
                <GradientStop Color="#E8D8BC" Offset="1"/>
              </LinearGradientBrush>
            </Grid.Background>
            <Rectangle Width="31" Height="2" RadiusX="1" RadiusY="1" Fill="#CDBD9E"
                       HorizontalAlignment="Center" VerticalAlignment="Top" Margin="0,21,0,0"/>
            <Rectangle Width="31" Height="2" RadiusX="1" RadiusY="1" Fill="#D7C8AD"
                       HorizontalAlignment="Center" VerticalAlignment="Bottom" Margin="0,0,0,21"/>
            <TextBlock Name="LeverText" Text="" Visibility="Collapsed"/>
          </Grid>
        </Border>
      </Canvas>
    </Border>
    <TextBlock Grid.Row="3" VerticalAlignment="Bottom" HorizontalAlignment="Center" Margin="0,0,0,0"
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
                       Text="Measure background CPU/disk activity and pick which apps to close."/>
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
$Script:TargetPath  = ''
$Script:IsOn        = Test-Path $Script:StateFile

$Script:TierHex = @{ Normal = '#2EA043'; High = '#D29922'; Extreme = '#DA3633' }

$TierInfo = @{
    Normal  = 'Stable FPS basics: Game Mode on, capture off, and a safe game priority boost. Closes and stops nothing.'
    High    = 'Recommended. Adds narrow AC performance tuning, pauses indexing/capture services, and closes common background apps.'
    Extreme = 'For CPU-limited PCs. Adds update-download cleanup and closes browsers, while avoiding RAM trimming and dangerous global priority tricks.'
}

# Color / brush helpers (hex -> WPF objects)
function New-Color([string]$hex) { return [Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex) }
function New-Brush([string]$hex) { return New-Object Windows.Media.SolidColorBrush ([Windows.Media.Color][Windows.Media.ColorConverter]::ConvertFromString($hex)) }

function Set-SwitchPose([bool]$on) {
    if ($on) {
        [Windows.Controls.Canvas]::SetTop($Lever, 62)
    } else {
        [Windows.Controls.Canvas]::SetTop($Lever, 82)
    }
    [Windows.Controls.Canvas]::SetLeft($Lever, 57)
    $Lever.RenderTransform = $null
}

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
        Set-SwitchPose $true
        $Lever.Background     = New-Brush '#FFF7E8'
        $LeverText.Text       = ''
        $Led.Fill             = New-Brush $hex
        $glow = New-Object Windows.Media.Effects.DropShadowEffect
        $glow.Color = New-Color $hex; $glow.BlurRadius = 22; $glow.ShadowDepth = 0; $glow.Opacity = 1
        $Led.Effect           = $glow
        $SwitchPlate.BorderBrush = New-Brush '#B8AA91'
        $LblOn.Foreground     = New-Brush $hex
        $LblOff.Foreground    = New-Brush '#9A8D77'
        $StatusLine.Text      = "Boosted ($($Script:Tier)). Your PC is focused on the game."
    } else {
        Set-SwitchPose $false
        $Lever.Background     = New-Brush '#F8F0E2'
        $LeverText.Text       = ''
        $Led.Fill             = New-Brush '#AFA187'
        $Led.Effect           = $null
        $SwitchPlate.BorderBrush = New-Brush '#B8AA91'
        $LblOn.Foreground     = New-Brush '#9A8D77'
        $LblOff.Foreground    = New-Brush '#6E624F'
        $StatusLine.Text      = "Idle. Pick a tier, then flip the switch."
    }
}

$Script:WatcherBoosted = @{}
function Apply-GBTargetPriorityWatcher {
    if (-not $Script:IsOn) { return }
    if (-not (Test-Path $Script:StateFile)) { return }
    try {
        $state = Get-Content -Path $Script:StateFile -Raw | ConvertFrom-Json
        $target = [string]$state.target
        if (-not $target) { return }
        foreach ($p in (Get-Process -Name $target -ErrorAction SilentlyContinue)) {
            $key = "$($p.Id)|$(Get-GBStartIso $p)"
            if ($Script:WatcherBoosted.ContainsKey($key)) { continue }
            if (Set-GBProcessPriority $state $p 'AboveNormal') {
                $Script:WatcherBoosted[$key] = $true
                Write-GBLog "Watcher: game '$target' priority -> AboveNormal"
            }
        }
    } catch { }
}

# Modal Deep Scan review dialog. Returns a confirmed result object so choosing
# zero apps is distinct from cancelling the dialog.
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
        $ScanHdr.Text = "Found $($candidates.Count) app(s). The $preCount with sustained CPU/disk activity are pre-checked; RAM alone never selects an app. Untick anything you want to keep.$warn"
        foreach ($c in $candidates) {
            $cb = New-Object Windows.Controls.CheckBox
            $cb.Foreground = New-Brush '#C9D1D9'
            $cb.Margin     = '2,4,2,4'
            $cb.Tag        = [pscustomobject]@{ Name = [string]$c.Name; Path = [string]$c.Path }
            $cb.IsChecked  = [bool]$c.Preselect
            $extra = if ($c.Count -gt 1) { "  (x$($c.Count))" } else { '' }
            if ($c.HasWindow) { $extra += '  [open window]' }
            $cb.Content = ('{0}{1}   -   {2} MB   -   {3}% CPU   -   {4} MB/s disk' -f $c.Name, $extra, $c.RamMB, $c.CpuPct, $c.DiskMBps)
            $ScanList.Children.Add($cb) | Out-Null
            $checks += $cb
        }
    }

    $result = @{ confirmed = $false; names = @() }
    $SelAll.Add_Click({  foreach ($c in $checks) { $c.IsChecked = $true } })
    $SelNone.Add_Click({ foreach ($c in $checks) { $c.IsChecked = $false } })
    $UseBtn.Add_Click({
        $sel = @()
        foreach ($c in $checks) { if ($c.IsChecked) { $sel += $c.Tag } }
        $result.names = $sel
        $result.confirmed = $true
        $dlg.DialogResult = $true
        $dlg.Close()
    }.GetNewClosure())

    $null = $dlg.ShowDialog()
    if (-not $result.confirmed) { return $null }
    return [pscustomobject]@{ Confirmed = $true; Names = @($result.names) }
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
                    try { $Script:TargetPath = [string]$fg.Path } catch { $Script:TargetPath = '' }
                    if (-not $Script:TargetPath) { $Script:TargetPath = Get-GBProcessPathByName $target }
                    Write-GBLog "Game set to '$target' (excluded from scan)"
                }
            }
        }

        $ScanInfo.Text = 'Scanning processes...'
        $ScanBtn.Dispatcher.Invoke([action]{}, 'Render')
        $scanOpts = @{ Target = $target; KeepDiscord = $Script:KeepDiscord }
        $scanResult = Show-ScanDialog $scanOpts $win
        if ($null -ne $scanResult) {
            $names = @($scanResult.Names)
            $Script:ScanKill = $names
            if ($names.Count -gt 0) {
                $ScanInfo.Text = "$($names.Count) app(s) queued - they close when you flip the switch."
                Write-GBLog "Deep Scan: armed $($names.Count) app(s) to close on flip"
            } else {
                $ScanInfo.Text = "Nothing queued. Scan again any time."
            }
        } else {
            $ScanInfo.Text = "Measure background CPU/disk activity and pick which apps to close."
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

$TxtTarget.Add_TextChanged({
    if (-not $Script:IsOn) { $Script:TargetPath = '' }
})

# --- Flip the switch ---
$flip = {
    if ($Script:Busy) { return }
    if (-not $Script:IsOn -and (Test-Path $Script:StateFile)) {
        $Script:IsOn = $true
        Write-GBLog "Recovery state found. Flip OFF to restore it before starting another boost."
        Update-SwitchUI
        return
    }
    $Script:Busy = $true
    $wasOn = $Script:IsOn
    try {
        if ($Script:IsOn) {
            $Script:IsOn = -not [bool](Disable-GameBoost)
        } else {
            $target = ($TxtTarget.Text).Trim() -replace '\.exe$',''
            if ($target -and -not $Script:TargetPath) { $Script:TargetPath = Get-GBProcessPathByName $target }
            $opts = Get-TierOptions $Script:Tier $target $Script:KeepDiscord $Script:TargetPath
            $opts.ScanKill = $Script:ScanKill
            if ($Script:KeepDiscord) { Write-GBLog "Discord protected (won't be closed or slowed)" }
            if ($Script:Tier -eq 'Extreme') { Write-GBLog "Applying EXTREME - aggressive cleanup without RAM trimming or Explorer restart..." }
            Enable-GameBoost $opts
            $Script:IsOn = $true
        }
    } catch {
        Write-GBLog "ERROR: $($_.Exception.Message)"
        if (-not $wasOn -and (Test-Path $Script:StateFile)) {
            Write-GBLog "Enable was interrupted - rolling back recorded changes now..."
            $Script:IsOn = $true
            try { $Script:IsOn = -not [bool](Disable-GameBoost) }
            catch { Write-GBLog "Automatic rollback failed; recovery state was kept for OFF." }
        } else {
            $Script:IsOn = Test-Path $Script:StateFile
        }
    } finally {
        Update-SwitchUI
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
        try { $Script:TargetPath = [string]$p.Path } catch { $Script:TargetPath = '' }
        if (-not $Script:TargetPath) { $Script:TargetPath = Get-GBProcessPathByName $p.ProcessName }
        if ($Script:TargetPath) {
            Write-GBLog "Detected game: $($p.ProcessName) ($([IO.Path]::GetFileName($Script:TargetPath)))"
        } else {
            Write-GBLog "Detected game: $($p.ProcessName)"
        }
    } else {
        Write-GBLog "Could not detect a game window."
    }
    $DetectBtn.Content = $orig
    $DetectBtn.IsEnabled = $true
})

$Script:PriorityWatcher = New-Object Windows.Threading.DispatcherTimer
$Script:PriorityWatcher.Interval = [TimeSpan]::FromSeconds(5)
$Script:PriorityWatcher.Add_Tick({ Apply-GBTargetPriorityWatcher })
$Script:PriorityWatcher.Start()

# If a boost is already active, reflect its tier + Discord choice
if ($Script:IsOn) {
    try {
        $saved = Get-Content -Path $Script:StateFile -Raw | ConvertFrom-Json
        if ($saved.tier) { $Script:Tier = [string]$saved.tier }
        if ($saved.target) { $TxtTarget.Text = [string]$saved.target }
        if ($saved.targetPath) { $Script:TargetPath = [string]$saved.targetPath }
        if ($null -ne $saved.opts -and $null -ne $saved.opts.KeepDiscord) { $Script:KeepDiscord = [bool]$saved.opts.KeepDiscord }
    } catch { }
}

Update-TierUI
Update-DiscordUI
Update-SwitchUI
if ($Script:IsOn) {
    if ($saved.phase -eq 'enabling') {
        Write-GBLog "Interrupted enable recovered. Flip the switch OFF to roll back recorded changes."
    } else {
        Write-GBLog "Active $($Script:Tier) boost from earlier. Flip the switch to restore."
    }
} else {
    Write-GBLog "Ready. Pick a tier and flip the switch before you play."
}

$win.Add_Closed({
    try { $Script:InstanceMutex.ReleaseMutex() } catch { }
    try { $Script:InstanceMutex.Dispose() } catch { }
})

$win.ShowDialog() | Out-Null
