# GameBoost

A one-switch performance booster for Windows with three tiers. Pick a tier,
flip the switch **ON** before you play, and **OFF** when you're done — it puts
everything back exactly how it was.

## How to use

1. Double-click **`GameBoost.bat`**.
2. Click **Yes** on the Windows admin (UAC) prompt.
3. Pick a tier: **NORMAL**, **HIGH**, or **EXTREME**.
4. Leave **Keep Discord running** ON if you use Discord to talk (it's on by
   default) — Discord won't be closed or slowed.
5. (Optional) Click **Detect (3s)** and alt-tab to your game, or type the
   game's `.exe` name, so GameBoost knows what to prioritize.
6. **Flip the light switch** — click it to slide the lever up. The LED lights
   up in the tier's color and the boost runs. Play.
7. When done, reopen GameBoost and flip the switch back down to turn it **OFF**.

> The boost stays active even if you close the window. Reopen GameBoost and the
> switch shows it's still ON (in the right tier) so you can flip it OFF.

## The light switch + Discord toggle

The whole UI is a wall switch: **up = ON** (LED glows in your tier color),
**down = OFF**. The tier you pick colors the switch — green (Normal), amber
(High), red (Extreme).

The **Keep Discord running** box is on by default. When it's ON, Discord (and
its voice helpers) are never closed by the bloat-killer and never slowed by the
Extreme priority pass, so your voice chat stays smooth. Turn it OFF only if you
want Extreme to close Discord too for maximum free RAM.

## The three tiers

### 🟢 NORMAL — light touch
For when you just need a small nudge. Nothing gets closed.
- High Performance power plan
- Stops a few junk services (telemetry, search indexer, SuperFetch, maps)
- Disables Game DVR / background recording
- Raises your game's CPU priority

### 🟡 HIGH — recommended for most
Everything in Normal, plus:
- Stops the **full** background-service list (print spooler, error reporting,
  compatibility assistant, media sharing, etc.)
- Closes background **bloat apps** (OneDrive, Teams, Spotify, Dropbox, Slack,
  Zoom, Phone Link, Widgets...)

### 🔴 EXTREME — maximum, built for weak PCs
Everything in High, plus the heavy hitters:
- **Ultimate Performance** power plan (auto-created the first time)
- **Extended service shutdown** — Windows Update, BITS, Delivery Optimization,
  geolocation, biometrics, sensors, and more
- **Frees RAM** — trims the working set of every background process and reports
  roughly how many MB it gave back
- **Lowers every other app's CPU priority** to BelowNormal so your game gets the
  cores (anti-cheat, audio, and core UI are protected and never touched)
- **Strips visual effects** — animations, transparency, window drag effects off
- **Network latency tweaks** — disables network throttling, maxes system
  responsiveness for games
- **Restarts Explorer** to reclaim its memory (your taskbar will blink once)
- **Closes heavy apps including web browsers** (Chrome, Edge, Firefox, Discord,
  Office...)

> Extreme is aggressive on purpose. Your screen will flicker once when Explorer
> restarts — that's normal. Turning the switch OFF reverses all of it.

## Is it safe?

Yes — it's deliberately conservative under the hood:
- **Never** touches critical Windows processes (it can't crash your PC).
- **Never** disables your antivirus.
- Game priority is set to **High**, never **Realtime** (which can freeze a PC).
- Anti-cheat (EasyAntiCheat, BattlEye, Vanguard), audio, and core UI are on a
  protect-list and are never de-prioritized.
- Every change is **saved to disk and reversed** when you flip OFF.
- A reboot also resets power plan, priorities, and services — always a clean
  fallback.

## Customizing

Open `GameBoost.ps1` in any text editor and edit the lists near the top:
- `$SvcLight` / `$SvcStandard` / `$SvcExtended` — services per tier
  (remove `'Spooler'` if you print while gaming).
- `$BloatStandard` / `$BloatExtended` — apps to close (add `'obs64'`, remove
  the browsers, etc.).
- `$ProtectNames` — processes Extreme will never de-prioritize (add your
  anti-cheat or voice app if needed).

## Notes

- For the **priority boost**, the game should be running when you flip ON (or
  detect it first). Launch the game afterward? Just flip OFF then ON again.
- State is stored in `%LOCALAPPDATA%\GameBoost\state.json`.
- **Extreme closes your browser** — save your tabs first. Don't use Extreme if
  you're following a video guide in your browser while playing.
