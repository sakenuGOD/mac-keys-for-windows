# Mac Keys for Windows

Tiny Windows utility that makes hotkeys feel like on a Mac. Lives in the tray, starts at logon, fully driven by a config file.

Mapping is **by physical key position next to the space bar**:

| Mac            | Windows       |
|----------------|---------------|
| `Cmd`          | `Alt`         |
| `Option`       | `Win`         |
| `Ctrl`         | `Ctrl`        |

So on Windows you press `Alt+C` — the utility sends `Ctrl+C`, and that copies in any app. Same goes for save, paste, find, new tab, screenshots, jump to line start/end, and so on.

## Install

### Option 1 — prebuilt exe (recommended)

1. Download `mac-keys-for-windows.zip` from the Releases page and extract it anywhere (e.g. `C:\Tools\mac-keys-for-windows\`).
2. Right-click `install.ps1` → **Run with PowerShell**. If Windows complains about the execution policy, open PowerShell and run:
   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```
3. On first launch a dialog appears: **"Enable auto-start at Windows logon?"** — Yes/No. Yes registers a Scheduled Task (UAC asks for confirmation), No — just runs in the current session. You can toggle it later from the settings window (the **Run at Windows logon** checkbox) or from the tray (**Run on startup**).
4. A coloured icon shows up in the tray: **green** = active, **yellow** = paused, **red** = disabled.

### Option 2 — from source

1. Install [AutoHotkey v2](https://www.autohotkey.com/).
2. Clone the repo anywhere.
3. Run `install.ps1` the same way — the script finds AHK itself and registers a task pointing at `mac-keys.ahk`.

### Uninstall

Run `uninstall.ps1`. The startup task is removed and the process stops. Config and log stay in `%APPDATA%\mac-keys-for-windows\` — delete manually if you don't want them.

## Usage

**Left-click the tray icon** — opens a mini settings window:

- status (Active / Paused / Disabled, with a coloured dot),
- four checkboxes: **Enabled (master)**, **Auto-pause in fullscreen apps**, **Smart gating**, **Run at Windows logon**,
- two lists: **Excluded apps** and **Fullscreen whitelist** with "Add current app" / "Remove selected" buttons,
- at the bottom: Edit config / Reload / Log / Quit.

**Global hotkeys:**

- `Ctrl+Alt+Shift+M` — master toggle (enable/disable).
- `Ctrl+Alt+Shift+Q` — kill-switch, fully exits the utility.

**Right-click the tray icon** — standard tray menu:

- **Enabled** — master switch. Mirrored by the `Ctrl+Alt+Shift+M` hotkey (configurable).
- **Pause for 30 seconds / Resume** — temporarily hands Alt back to Windows without fully disabling.
- **Disable in current app** — adds the active process to `excludedApps`; the utility ignores it entirely.
- **Keep active in current app (fullscreen)** — adds it to `fullscreenWhitelist`. Useful when the app goes fullscreen (F11) but you still want the hotkeys there (browsers, video players).
- **Auto-pause in fullscreen** — toggles auto-pause when a non-whitelisted process is fullscreen (game heuristic).
- **Open config.json** — opens the file in notepad. Save it and the utility auto-reloads; changes apply immediately.
- **Run at Windows logon** — registers/unregisters the Scheduled Task.

## How we avoid breaking games

In games `Alt` is often a native key (crouch, voice, walk). Naively rebinding `Alt+C → Ctrl+C` globally breaks them. Protection has five layers, **without any hardcoded list of game names**:

1. **Smart gating (universal).** The utility always knows how long Alt has been held and whether WASD was pressed during the hold.
   - `< 250 ms` of Alt held → this is a shortcut, fire it (`Alt+C → Ctrl+C`).
   - `> 800 ms` held, or WASD pressed during the hold → this is a game-key, **let the native Alt through to the game** (sends `{Blind}c` without the modifier).
   - Grey zone (250–800 ms without WASD) — decided by movement.
   Thresholds live in `config.smartGating`.
2. **Auto-pause in fullscreen.** The utility checks the focused window: if it fills the monitor and has no title bar → pause. Covers most games (exclusive and borderless fullscreen).
3. **Whitelist of processes that can be ignored**: browsers, video players, IDEs, office apps. Fullscreen in those doesn't trigger pause.
4. **Blacklist of processes** where the utility never runs: RDP, VMware, VirtualBox, Parsec, AnyDesk, TeamViewer. Input passes through.
5. **Master toggle and kill-switch.** `Ctrl+Alt+Shift+M` — pause/resume, `Ctrl+Alt+Shift+Q` — fully exit.

If a game still slipped through (windowed + non-standard window, say), open the settings window → "Add current app" to Excluded apps. One click.

## Config

File: `%APPDATA%\mac-keys-for-windows\config.json`.

```json
{
  "enabled": true,
  "autoPauseFullscreen": true,
  "smartGating": {
    "enabled": true,
    "altShortcutMaxMs": 250,
    "altGameMinMs": 800
  },
  "masterToggleHotkey": "^!+m",
  "quitHotkey": "^!+q",
  "excludedApps": ["mstsc.exe", "parsec.exe"],
  "fullscreenWhitelist": ["chrome.exe", "vlc.exe"],
  "bindings": [
    { "from": "!c", "to": "^c", "enabled": true, "desc": "copy" },
    { "from": "!+4", "to": "#+s", "enabled": true, "desc": "screenshot region" }
  ]
}
```

### Hotkey notation (AutoHotkey v2)

| Symbol | Meaning     |
|--------|-------------|
| `^`    | Ctrl        |
| `!`    | Alt         |
| `+`    | Shift       |
| `#`    | Win         |
| `{F4}` | named key   |
| `Space`, `Left`, `Right`, `Up`, `Down`, `Home`, `End`, `BackSpace`, `PrintScreen` | as-is |

Examples:
- `!c` = `Alt+C`
- `!+4` = `Alt+Shift+4`
- `!{F4}` = `Alt+F4`
- `#+s` = `Win+Shift+S`

No restart after editing config — the utility detects the file change and reloads itself within 2 seconds.

## What's mapped by default

- **Editing:** `Alt+C/V/X/A/Z/Shift+Z/S/Shift+S/W/Q/T/Shift+T/N/Shift+N/O/P/R/F/G/Shift+G/B/I/U/K/L`
- **Tabs:** `Alt+Shift+]` / `Alt+Shift+[` — next / previous tab
- **Screenshots:** `Alt+Shift+3` (fullscreen), `Alt+Shift+4` and `Alt+Shift+2` (region), `Alt+Shift+5` (screen recording via Game Bar)
- **Search:** `Alt+Space` → `Win+S` (system search)
- **Navigation:** `Alt+←/→/↑/↓` — line start/end, document top/bottom; `Alt+Shift+←/→/↑/↓` — same with selection
- **By word (Option+←/→):** `Win+←/→` — move, `Win+Shift+←/→` — with selection, `Win+Backspace` — delete previous word
- **Backspace:** `Alt+Backspace` — delete word (like on Mac)

Everything is editable in `config.json`. Any entry can be turned off with `"enabled": false`.

## Important caveats

- **Alt+F opens Find, not the File menu.** The cost of Mac-style mapping. Access the menu with `F10` or the mouse. If it really gets in the way, set `"enabled": false` on the `!f` binding — File menu comes back.
- **Alt+Space** is captured for system search, so the native window system menu (move/minimise) via `Alt+Space` is no longer available. Use the title-bar buttons or `Win+arrow`.
- **Utility only works while running.** It's not a kernel driver — quitting via the tray restores native Windows behaviour.
- **Auto-start is opt-in and explicit.** First run asks in a separate dialog, no silent registration. If you agree, UAC separately asks for confirmation to create a Scheduled Task with HighestAvailable. Admin rights are needed for hotkeys to work in elevated windows (Task Manager, regedit). Without auto-start it just runs in the current session.

## Log and debugging

`%APPDATA%\mac-keys-for-windows\mac-keys.log` — plain text log (starts, binding errors, config reloads).

If a hotkey doesn't fire:
1. Check the log for a registration error.
2. Check whether the app ended up in `excludedApps`.
3. Make sure the utility isn't paused (tray icon).
4. If the app is elevated (admin), the utility needs to be elevated too (that's what the Scheduled Task solves).

## License

MIT. See [LICENSE](LICENSE).
