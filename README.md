# GameBoost

GameBoost is a reversible Windows gaming performance helper. Pick a tier, flip
the switch ON before playing, and flip it OFF when finished. It focuses on
reducing real CPU, disk, and network contention instead of using RAM cleaners or
registry folklore that can make frame times worse.

No utility can manufacture GPU performance. GameBoost is most useful when a
game is CPU-limited or Windows and background apps are competing for resources.
If a game is already GPU-bound and the PC is otherwise idle, average FPS may not
change. The more realistic win in that case is fewer background spikes.

## How to use

1. Double-click **`GameBoost.bat`**.
2. Accept the Windows administrator prompt.
3. Pick **NORMAL**, **HIGH**, or **EXTREME**.
4. Leave **Keep Discord running** on if you use voice chat.
5. Click **Detect (3s)** and focus the running game, or type its process name.
6. Optionally run **Deep scan** and review extra apps to close.
7. Flip the light switch up to turn the boost ON.
8. Leave GameBoost open or minimized if the named game has not started yet; its
   low-frequency watcher will apply the priority after the process appears.
9. Flip the switch down when finished. OFF restores the tracked state.

If no game is entered, service and app cleanup still works, but no process
priority is changed. GameBoost deliberately does not poll GPU counters during
play because that monitoring can create the periodic work this tool is meant to
remove.

## What ON does

All tiers:

- Enables Game Mode and disables Game DVR background capture for the session.
- Sets the selected game to **AboveNormal** priority. It deliberately avoids
  High and Realtime priorities, which can starve audio, drivers, and Windows.

HIGH additionally:

- Clones the current power plan into a temporary copy and changes only two AC
  processor settings: maximum state and documented energy-performance
  preference. OEM thermal, battery, storage, PCIe, USB, Wi-Fi, boost-mode, and
  minimum-processor policies remain untouched.
- Temporarily stops active search indexing, telemetry, Game DVR capture, maps,
  and error-reporting services.
- Closes known background apps such as OneDrive, Teams, Spotify, Dropbox, Slack,
  Zoom, Phone Link, Widgets, and Game Bar helpers.

EXTREME additionally:

- Uses the performance end of the documented AC energy-performance preference.
- Pauses Windows Update, BITS, and Delivery Optimization only when no Windows
  servicing process is active.
- Closes browsers, Adobe helpers, and other heavier background apps. Peripheral,
  fan/profile, launcher, and GPU-driver utilities are left alone.

Extreme is intentionally aggressive, but it still does not disable antivirus,
kill Windows core processes, trim working sets, restart Explorer, force global
priority changes, or apply speculative network tweaks.

## Deep scan

Deep scan samples current CPU, working memory, and disk I/O, then lists
non-essential user-session processes. The game, Windows core, security, drivers,
anti-cheat, launchers, Discord when protected, and capture/audio tools are
excluded.

Resource-heavy background processes are preselected. Apps with a visible window
are labeled and are not preselected, reducing the chance of closing unsaved
work. RAM size alone never preselects an app; selection requires measured CPU or
disk activity. You still control the final selection.

## Restoration

Before each change, GameBoost atomically updates
`%LOCALAPPDATA%\GameBoost\state.json`. OFF uses that ledger to:

- Reactivate the exact previous power plan and remove the temporary copy.
- Restart only services that were running before ON.
- Restore only process priorities that GameBoost changed, matching both PID and
  process start time.
- Restore original registry values, removing values that did not exist before.
- Preserve a registry value if Windows or the user changed it again while ON.
- Relaunch apps that GameBoost closed when Windows exposes a valid executable
  path.

Visible apps receive a normal close request first; GameBoost does not force them
closed if they refuse. Background helper processes may be force-closed. Relaunch
can restore the application process, but no tool can reconstruct unsaved in-app
state. Save work before using Extreme or manually selecting an app in Deep scan.

If a meaningful restore action fails, GameBoost keeps the recovery file and
leaves the switch ON so OFF can be tried again instead of discarding the state.

## Customizing

The configuration lists are near the top of `GameBoost.ps1`:

- `$Script:SvcLight`, `$Script:SvcStandard`, `$Script:SvcExtended`: services by
  tier. Remove update services from Extreme if downloads must continue.
- `$Script:BloatStandard`, `$Script:BloatExtended`: apps closed by tier.
- `$Script:ProtectNames` and `$Script:ScanProtect`: processes that remain
  untouched.

## Technical choices

Microsoft warns that High process priority can consume nearly all available CPU
time, so GameBoost uses AboveNormal. Microsoft also documents that MMCSS High
scheduling is intended for Pro Audio and that its GPU Priority and SFIO Priority
values are not used, so GameBoost does not overwrite the Windows Games profile.
The temporary plan uses documented processor energy-performance preference
settings.

References:

- [Process priority classes](https://learn.microsoft.com/en-us/dotnet/api/system.diagnostics.processpriorityclass)
- [Multimedia Class Scheduler Service](https://learn.microsoft.com/en-us/windows/win32/procthread/multimedia-class-scheduler-service)
- [Processor energy-performance preference](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/options-for-perf-state-engine-perfenergypreference)
- [Processor power-management guidance](https://learn.microsoft.com/en-us/windows-hardware/customize/power-settings/configure-processor-power-management-options)
- [Windows service configuration guidance](https://learn.microsoft.com/en-us/windows/iot/iot-enterprise/optimize/services)
- [Microsoft Windows performance guidance](https://support.microsoft.com/en-us/windows/tips-to-improve-pc-performance-in-windows-b3b3ef5b-5953-fb6a-2528-4bbed82fba96)

## License

GameBoost is free and open source under the **MIT License**. Anyone may use,
modify, distribute, or build on it as long as the license notice is retained.
See [`LICENSE`](LICENSE) for the full terms.
