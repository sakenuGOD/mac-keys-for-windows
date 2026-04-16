#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

#Include lib\json.ahk

; =============================================================================
; Constants
; =============================================================================
APP_DISPLAY := "Mac Keys for Windows"
APP_VERSION := "0.2.0"
APP_ID      := "mac-keys-for-windows"
TASK_NAME   := "MacKeysForWindows"

CONFIG_DIR     := EnvGet("APPDATA") . "\" . APP_ID
CONFIG_PATH    := CONFIG_DIR . "\config.json"
LOG_PATH       := CONFIG_DIR . "\mac-keys.log"
DEFAULT_CONFIG := A_ScriptDir . "\config.default.json"

ICON_ON     := A_ScriptDir . "\assets\icon-on.ico"
ICON_OFF    := A_ScriptDir . "\assets\icon-off.ico"
ICON_PAUSED := A_ScriptDir . "\assets\icon-paused.ico"

; =============================================================================
; State
; =============================================================================
global Config            := Map()
global Enabled           := true
global Paused            := false
global PauseUntil        := 0
global ConfigMTime       := 0
global AltDownTime       := 0
global MovementDuringAlt := false
global MainGui           := ""
global GuiCtrls          := Map()

; =============================================================================
; Entry point
; =============================================================================
Main()

Main() {
    global ConfigMTime
    EnsureConfigDir()
    firstRun := EnsureDefaultConfig()
    LoadConfig()
    ConfigMTime := FileGetTime(CONFIG_PATH, "M")

    RegisterMasterToggle()
    RegisterQuitHotkey()
    RegisterAltTracker()
    RegisterMovementTrackers()
    RegisterBindings()
    BuildTrayMenu()
    UpdateTrayIcon()

    SetTimer CheckPauseExpiry, 500
    SetTimer WatchConfigFile, 2000
    Log("started v" APP_VERSION)

    if firstRun
        FirstRunSetup()
}

FirstRunSetup() {
    ; Не регистрируем задачу молча — спрашиваем у пользователя.
    ; Любая elevated-персистенция должна быть осознанной.
    if IsTaskRegistered() {
        try TrayTip "Mac Keys for Windows is running.`nClick the tray icon to open settings.", APP_DISPLAY, 1
        return
    }

    msg := "Mac Keys for Windows установлен и работает.`n`n"
        . "Включить автозапуск при входе в Windows?`n"
        . "(будет создана Scheduled Task; для повышенных прав потребуется UAC)`n`n"
        . "Можно изменить позже через окно настроек или трей."
    answer := MsgBox(msg, APP_DISPLAY, "YesNo Icon? 0x40000")
    if answer = "Yes" {
        RegisterTask()
        if IsTaskRegistered()
            try TrayTip "Автозапуск включён. Иконка в трее.", APP_DISPLAY, 1
    } else {
        try TrayTip "Автозапуск пропущен. Можно включить позже из окна настроек.", APP_DISPLAY, 1
    }
}

; =============================================================================
; Config I/O
; =============================================================================
EnsureConfigDir() {
    if !DirExist(CONFIG_DIR)
        DirCreate CONFIG_DIR
}

EnsureDefaultConfig() {
    if FileExist(CONFIG_PATH)
        return false
    if FileExist(DEFAULT_CONFIG) {
        FileCopy DEFAULT_CONFIG, CONFIG_PATH
        return true
    }
    fallback := '{"enabled":true,"autoPauseFullscreen":true,"smartGating":{"enabled":true,"altShortcutMaxMs":250,"altGameMinMs":800,"movementKeys":["w","a","s","d","Space"]},"masterToggleHotkey":"^!+m","quitHotkey":"^!+q","excludedApps":[],"fullscreenWhitelist":[],"bindings":[]}'
    FileAppend fallback, CONFIG_PATH, "UTF-8"
    return true
}

LoadConfig() {
    global Config, Enabled
    try {
        text := FileRead(CONFIG_PATH, "UTF-8")
        Config := Json.Parse(text)
    } catch Error as e {
        MsgBox "Failed to read config.json:`n" e.Message "`n`nUsing default config.", APP_DISPLAY, "Icon!"
        text := FileRead(DEFAULT_CONFIG, "UTF-8")
        Config := Json.Parse(text)
    }
    if !Config.Has("enabled")
        Config["enabled"] := true
    if !Config.Has("autoPauseFullscreen")
        Config["autoPauseFullscreen"] := true
    if !Config.Has("excludedApps")
        Config["excludedApps"] := []
    if !Config.Has("fullscreenWhitelist")
        Config["fullscreenWhitelist"] := []
    if !Config.Has("bindings")
        Config["bindings"] := []
    if !Config.Has("masterToggleHotkey")
        Config["masterToggleHotkey"] := "^!+m"
    if !Config.Has("quitHotkey")
        Config["quitHotkey"] := "^!+q"
    if !Config.Has("smartGating") {
        Config["smartGating"] := Map(
            "enabled", true,
            "altShortcutMaxMs", 250,
            "altGameMinMs", 800,
            "movementKeys", ["w","a","s","d","Space"]
        )
    } else {
        sg := Config["smartGating"]
        if !sg.Has("enabled")          sg["enabled"] := true
        if !sg.Has("altShortcutMaxMs") sg["altShortcutMaxMs"] := 250
        if !sg.Has("altGameMinMs")     sg["altGameMinMs"] := 800
        if !sg.Has("movementKeys")     sg["movementKeys"] := ["w","a","s","d","Space"]
    }
    Enabled := Config["enabled"]
}

SaveConfig() {
    global Config, ConfigMTime
    text := Json.Stringify(Config, "  ")
    try FileDelete CONFIG_PATH
    FileAppend text, CONFIG_PATH, "UTF-8"
    ConfigMTime := FileGetTime(CONFIG_PATH, "M")
}

; =============================================================================
; Hotkey registration — master, quit, Alt tracker, movement tracker, bindings
; =============================================================================
RegisterMasterToggle() {
    global Config
    HotIf
    try Hotkey Config["masterToggleHotkey"], MasterToggleHandler, "On"
    catch
        Log("failed to register master toggle: " Config["masterToggleHotkey"])
}

RegisterQuitHotkey() {
    global Config
    HotIf
    try Hotkey Config["quitHotkey"], QuitHotkeyHandler, "On"
    catch
        Log("failed to register quit hotkey: " Config["quitHotkey"])
}

RegisterAltTracker() {
    HotIf
    try {
        Hotkey "~LAlt",    OnAltDown, "On"
        Hotkey "~LAlt Up", OnAltUp,   "On"
        Hotkey "~RAlt",    OnAltDown, "On"
        Hotkey "~RAlt Up", OnAltUp,   "On"
    }
}

RegisterMovementTrackers() {
    global Config
    HotIf MovementCtx
    for k in Config["smartGating"]["movementKeys"] {
        try Hotkey "~*" k, MarkMovement, "On"
    }
    HotIf
}

MovementCtx(hk) {
    global AltDownTime
    return AltDownTime > 0
}

OnAltDown(*) {
    global AltDownTime, MovementDuringAlt
    if !AltDownTime
        AltDownTime := A_TickCount
    MovementDuringAlt := false
}

OnAltUp(*) {
    global AltDownTime, MovementDuringAlt
    AltDownTime := 0
    MovementDuringAlt := false
}

MarkMovement(*) {
    global MovementDuringAlt
    MovementDuringAlt := true
}

RegisterBindings() {
    global Config
    HotIf IsActiveCtx
    for b in Config["bindings"] {
        if !(b is Map) || !b.Has("from") || !b.Has("to")
            continue
        if b.Has("enabled") && !b["enabled"]
            continue
        from := b["from"]
        to   := b["to"]
        try {
            Hotkey from, CreateHandler(to, ExtractOriginalKey(from), HasAltMod(from)), "On"
        } catch Error as e {
            Log("bad binding " from " -> " to ": " e.Message)
        }
    }
    HotIf
}

CreateHandler(target, originalKey, altMod) {
    return (*) => SendTarget(target, originalKey, altMod)
}

SendTarget(target, originalKey, altMod) {
    global Config
    if (altMod && Config["smartGating"]["enabled"] && IsGameIntent()) {
        SendBlindKey(originalKey)
    } else {
        try Send target
    }
}

SendBlindKey(originalKey) {
    if originalKey = ""
        return
    if StrLen(originalKey) > 1
        Send "{Blind}{" originalKey "}"
    else
        Send "{Blind}" originalKey
}

; =============================================================================
; Smart gating — universal game-vs-shortcut intent detection
; Two signals, no app lists:
;   1. How long Alt has been held when the letter is pressed.
;      < altShortcutMaxMs => always shortcut. > altGameMinMs => always game.
;   2. Whether a movement key (WASD/Space by default) was pressed during this
;      Alt-hold. Strong game indicator in the gray zone between the thresholds.
; =============================================================================
IsGameIntent() {
    global AltDownTime, MovementDuringAlt, Config
    if !AltDownTime
        return false
    holdMs := A_TickCount - AltDownTime
    sg := Config["smartGating"]
    if (holdMs < sg["altShortcutMaxMs"])
        return false
    if (holdMs > sg["altGameMinMs"])
        return true
    return MovementDuringAlt
}

ExtractOriginalKey(from) {
    s := from
    while StrLen(s) > 0 {
        c := SubStr(s, 1, 1)
        if (c = "^" || c = "!" || c = "+" || c = "#"
            || c = "<" || c = ">" || c = "*" || c = "~" || c = "$")
            s := SubStr(s, 2)
        else
            break
    }
    if (StrLen(s) >= 2 && SubStr(s, 1, 1) = "{" && SubStr(s, -1) = "}")
        s := SubStr(s, 2, StrLen(s) - 2)
    return s
}

HasAltMod(from) {
    for c in StrSplit(from) {
        if (c = "!")
            return true
        if (c = "^" || c = "+" || c = "#" || c = "<" || c = ">" || c = "*" || c = "~" || c = "$")
            continue
        return false
    }
    return false
}

; =============================================================================
; Active context gate
; =============================================================================
IsActiveCtx(hotkeyName) {
    return IsActive()
}

IsActive() {
    global Enabled, Paused, PauseUntil, Config
    if !Enabled
        return false
    if Paused {
        if A_TickCount < PauseUntil
            return false
        Paused := false
        UpdateTrayIcon()
    }
    proc := GetActiveProcessNameLower()
    if proc = ""
        return true
    if IsInList(Config["excludedApps"], proc)
        return false
    if Config["autoPauseFullscreen"] && !IsInList(Config["fullscreenWhitelist"], proc) {
        if IsActiveWindowFullscreen()
            return false
    }
    return true
}

; =============================================================================
; Helpers
; =============================================================================
GetActiveProcessNameLower() {
    try {
        proc := WinGetProcessName("A")
        return StrLower(proc)
    } catch {
        return ""
    }
}

IsInList(list, needle) {
    if !(list is Array)
        return false
    needleL := StrLower(needle)
    for item in list {
        if StrLower(item) = needleL
            return true
    }
    return false
}

AddToList(listKey, value) {
    global Config
    if !Config.Has(listKey)
        Config[listKey] := []
    for item in Config[listKey] {
        if StrLower(item) = StrLower(value)
            return false
    }
    Config[listKey].Push(value)
    return true
}

RemoveFromList(listKey, value) {
    global Config
    if !Config.Has(listKey)
        return
    arr := Config[listKey]
    i := arr.Length
    while i >= 1 {
        if StrLower(arr[i]) = StrLower(value)
            arr.RemoveAt(i)
        i -= 1
    }
}

IsActiveWindowFullscreen() {
    try {
        hwnd := WinGetID("A")
        if !hwnd
            return false
        style := WinGetStyle("A")
        if (style & 0x00C00000)
            return false
        WinGetPos &x, &y, &w, &h, "A"
        cx := x + w // 2
        cy := y + h // 2
        loop MonitorGetCount() {
            MonitorGet A_Index, &mx, &my, &mr, &mb
            if (cx >= mx && cx < mr && cy >= my && cy < mb) {
                mw := mr - mx
                mh := mb - my
                return (w >= mw - 2 && h >= mh - 2)
            }
        }
    } catch {
        return false
    }
    return false
}

Log(line) {
    try {
        ts := FormatTime(, "yyyy-MM-dd HH:mm:ss")
        FileAppend ts " | " line "`n", LOG_PATH, "UTF-8"
    }
}

; =============================================================================
; Tray menu and icon
; =============================================================================
BuildTrayMenu() {
    global Config, Enabled
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("Show window", (*) => ShowMainGui())
    tray.Default := "Show window"
    tray.Add()

    tray.Add("Enabled", ToggleEnabledMenu)
    if Enabled
        tray.Check("Enabled")
    tray.Add("Pause for 30 seconds", Pause30sMenu)
    tray.Add("Resume", UnpauseMenu)
    tray.Add()

    tray.Add("Disable in current app", DisableInCurrentAppMenu)
    tray.Add("Keep active in current app (fullscreen)", KeepActiveInCurrentAppMenu)
    tray.Add("Auto-pause in fullscreen", ToggleAutoPauseMenu)
    if Config["autoPauseFullscreen"]
        tray.Check("Auto-pause in fullscreen")
    tray.Add("Smart gating (game-aware)", ToggleSmartGatingMenu)
    if Config["smartGating"]["enabled"]
        tray.Check("Smart gating (game-aware)")
    tray.Add()

    tray.Add("Open config.json", OpenConfigMenu)
    tray.Add("Reload config", ReloadMenu)
    tray.Add("Open log", OpenLogMenu)
    tray.Add()

    tray.Add("Run on startup", ToggleAutoStartMenu)
    if IsTaskRegistered()
        tray.Check("Run on startup")
    tray.Add()

    tray.Add("About", AboutMenu)
    tray.Add("Quit", QuitMenu)

    tray.ClickCount := 1
}

UpdateTrayIcon() {
    global Enabled, Paused, MainGui
    icon := ICON_ON
    if !Enabled
        icon := ICON_OFF
    else if Paused
        icon := ICON_PAUSED
    if FileExist(icon) {
        try TraySetIcon icon, , true
    } else {
        try TraySetIcon "shell32.dll", Enabled ? 44 : 132
    }
    A_IconTip := BuildTooltip()
    if MainGui
        try RefreshMainGui()
}

BuildTooltip() {
    global Enabled, Paused
    s := APP_DISPLAY
    if !Enabled
        return s " — OFF"
    if Paused
        return s " — paused"
    return s " — ON"
}

; =============================================================================
; Main GUI window — opens on tray click
; =============================================================================
ShowMainGui() {
    global MainGui, GuiCtrls, Config
    if MainGui {
        try {
            MainGui.Show()
            RefreshMainGui()
            return
        }
    }
    MainGui := Gui("+AlwaysOnTop -MaximizeBox", APP_DISPLAY)
    MainGui.SetFont("s10", "Segoe UI")
    MainGui.MarginX := 14
    MainGui.MarginY := 12

    MainGui.SetFont("s12 bold")
    MainGui.Add("Text", "w400", APP_DISPLAY)
    MainGui.SetFont("s10 norm")

    GuiCtrls["status"] := MainGui.Add("Text", "w400 cGreen", "● Active")

    GuiCtrls["enabled"] := MainGui.Add("CheckBox", "w400 y+12", "Enabled (master)")
    GuiCtrls["enabled"].OnEvent("Click", GuiToggleEnabled)
    GuiCtrls["autoPause"] := MainGui.Add("CheckBox", "w400", "Auto-pause in fullscreen apps")
    GuiCtrls["autoPause"].OnEvent("Click", GuiToggleAutoPause)
    GuiCtrls["smartGating"] := MainGui.Add("CheckBox", "w400", "Smart gating (auto-pass Alt during gameplay)")
    GuiCtrls["smartGating"].OnEvent("Click", GuiToggleSmartGating)
    GuiCtrls["autostart"] := MainGui.Add("CheckBox", "w400", "Run at Windows logon (Scheduled Task)")
    GuiCtrls["autostart"].OnEvent("Click", GuiToggleAutoStart)

    MainGui.Add("Text", "w400 y+15", "Excluded apps (no remapping at all):")
    GuiCtrls["exc"] := MainGui.Add("ListBox", "w400 h90")
    MainGui.Add("Button", "w130", "Add current app").OnEvent("Click", GuiAddExc)
    MainGui.Add("Button", "x+5 yp w130", "Remove selected").OnEvent("Click", GuiRemoveExc)

    MainGui.Add("Text", "xm w400 y+15", "Fullscreen whitelist (keep active in fullscreen):")
    GuiCtrls["wl"] := MainGui.Add("ListBox", "xm w400 h90")
    MainGui.Add("Button", "xm w130", "Add current app").OnEvent("Click", GuiAddWl)
    MainGui.Add("Button", "x+5 yp w130", "Remove selected").OnEvent("Click", GuiRemoveWl)

    MainGui.Add("Text", "xm w400 y+18 cGray",
        "Master toggle: " Config["masterToggleHotkey"] "    Quit: " Config["quitHotkey"])

    MainGui.Add("Button", "xm w95 y+10", "Edit config").OnEvent("Click", (*) => OpenConfigMenu())
    MainGui.Add("Button", "x+5 yp w70", "Reload").OnEvent("Click", (*) => ReloadMenu())
    MainGui.Add("Button", "x+5 yp w70", "Log").OnEvent("Click", (*) => OpenLogMenu())
    MainGui.Add("Button", "x+5 yp w70", "Quit").OnEvent("Click", (*) => QuitMenu())

    MainGui.OnEvent("Close", GuiClose)
    MainGui.OnEvent("Escape", GuiClose)

    RefreshMainGui()
    MainGui.Show()
}

GuiClose(*) {
    global MainGui
    try MainGui.Hide()
}

RefreshMainGui() {
    global MainGui, GuiCtrls, Config, Enabled, Paused
    if !MainGui
        return
    try {
        if !Enabled {
            GuiCtrls["status"].Opt("+cRed +Redraw")
            GuiCtrls["status"].Text := "● Disabled"
        } else if Paused {
            GuiCtrls["status"].Opt("+c808000 +Redraw")
            GuiCtrls["status"].Text := "● Paused"
        } else {
            GuiCtrls["status"].Opt("+cGreen +Redraw")
            GuiCtrls["status"].Text := "● Active"
        }
        GuiCtrls["enabled"].Value     := Enabled ? 1 : 0
        GuiCtrls["autoPause"].Value   := Config["autoPauseFullscreen"] ? 1 : 0
        GuiCtrls["smartGating"].Value := Config["smartGating"]["enabled"] ? 1 : 0
        GuiCtrls["autostart"].Value   := IsTaskRegistered() ? 1 : 0
        GuiCtrls["exc"].Delete()
        for app in Config["excludedApps"]
            GuiCtrls["exc"].Add([app])
        GuiCtrls["wl"].Delete()
        for app in Config["fullscreenWhitelist"]
            GuiCtrls["wl"].Add([app])
    }
}

GuiToggleEnabled(ctrl, *) {
    global Enabled, Config
    Enabled := (ctrl.Value = 1)
    Config["enabled"] := Enabled
    SaveConfig()
    BuildTrayMenu()
    UpdateTrayIcon()
}

GuiToggleAutoPause(ctrl, *) {
    global Config
    Config["autoPauseFullscreen"] := (ctrl.Value = 1)
    SaveConfig()
    BuildTrayMenu()
}

GuiToggleSmartGating(ctrl, *) {
    global Config
    Config["smartGating"]["enabled"] := (ctrl.Value = 1)
    SaveConfig()
    BuildTrayMenu()
}

GuiToggleAutoStart(ctrl, *) {
    ; Не молча. UAC-промпт schtasks при необходимости — это и есть явное
    ; подтверждение от пользователя на уровне ОС.
    ToggleAutoStartMenu()
}

GuiAddExc(*) {
    proc := GetActiveProcessNameLower()
    if (proc = "" || proc = "mac-keys.exe" || proc = "autohotkey.exe" || proc = "autohotkey64.exe") {
        try TrayTip "Could not detect a different active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("excludedApps", proc) {
        SaveConfig()
        RefreshMainGui()
        BuildTrayMenu()
    }
}

GuiRemoveExc(*) {
    global GuiCtrls
    sel := GuiCtrls["exc"].Text
    if sel = ""
        return
    RemoveFromList("excludedApps", sel)
    SaveConfig()
    RefreshMainGui()
    BuildTrayMenu()
}

GuiAddWl(*) {
    proc := GetActiveProcessNameLower()
    if (proc = "" || proc = "mac-keys.exe" || proc = "autohotkey.exe" || proc = "autohotkey64.exe") {
        try TrayTip "Could not detect a different active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("fullscreenWhitelist", proc) {
        SaveConfig()
        RefreshMainGui()
        BuildTrayMenu()
    }
}

GuiRemoveWl(*) {
    global GuiCtrls
    sel := GuiCtrls["wl"].Text
    if sel = ""
        return
    RemoveFromList("fullscreenWhitelist", sel)
    SaveConfig()
    RefreshMainGui()
    BuildTrayMenu()
}

; =============================================================================
; Tray actions
; =============================================================================
ToggleEnabledMenu(*) {
    global Enabled, Config
    Enabled := !Enabled
    Config["enabled"] := Enabled
    SaveConfig()
    BuildTrayMenu()
    UpdateTrayIcon()
}

Pause30sMenu(*) {
    global Paused, PauseUntil
    Paused := true
    PauseUntil := A_TickCount + 30000
    UpdateTrayIcon()
}

UnpauseMenu(*) {
    global Paused
    Paused := false
    UpdateTrayIcon()
}

CheckPauseExpiry() {
    global Paused, PauseUntil
    if Paused && A_TickCount >= PauseUntil {
        Paused := false
        UpdateTrayIcon()
    }
}

DisableInCurrentAppMenu(*) {
    proc := GetActiveProcessNameLower()
    if proc = "" {
        try TrayTip "Could not detect active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("excludedApps", proc) {
        SaveConfig()
        BuildTrayMenu()
        RefreshMainGui()
        try TrayTip proc " added to excludedApps.", APP_DISPLAY, 2
    } else {
        try TrayTip proc " already in list.", APP_DISPLAY, 2
    }
}

KeepActiveInCurrentAppMenu(*) {
    proc := GetActiveProcessNameLower()
    if proc = "" {
        try TrayTip "Could not detect active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("fullscreenWhitelist", proc) {
        SaveConfig()
        BuildTrayMenu()
        RefreshMainGui()
        try TrayTip proc " added to fullscreenWhitelist.", APP_DISPLAY, 2
    } else {
        try TrayTip proc " already in list.", APP_DISPLAY, 2
    }
}

ToggleAutoPauseMenu(*) {
    global Config
    Config["autoPauseFullscreen"] := !Config["autoPauseFullscreen"]
    SaveConfig()
    BuildTrayMenu()
    RefreshMainGui()
}

ToggleSmartGatingMenu(*) {
    global Config
    Config["smartGating"]["enabled"] := !Config["smartGating"]["enabled"]
    SaveConfig()
    BuildTrayMenu()
    RefreshMainGui()
}

OpenConfigMenu(*) {
    try Run 'notepad.exe "' CONFIG_PATH '"'
}

OpenLogMenu(*) {
    if !FileExist(LOG_PATH)
        FileAppend "", LOG_PATH, "UTF-8"
    try Run 'notepad.exe "' LOG_PATH '"'
}

ReloadMenu(*) {
    Reload
}

ToggleAutoStartMenu(*) {
    if IsTaskRegistered()
        UnregisterTask()
    else
        RegisterTask()
    BuildTrayMenu()
    RefreshMainGui()
}

AboutMenu(*) {
    global Config
    MsgBox APP_DISPLAY " v" APP_VERSION
        . "`n`nConfig:`n" CONFIG_PATH
        . "`n`nLog:`n" LOG_PATH
        . "`n`nMaster toggle: " Config["masterToggleHotkey"]
        . "`nQuit hotkey:   " Config["quitHotkey"], APP_DISPLAY, "Icon*"
}

QuitMenu(*) {
    Log("quit")
    ExitApp
}

; =============================================================================
; Master toggle and quit
; =============================================================================
MasterToggleHandler(*) {
    global Enabled, Config
    Enabled := !Enabled
    Config["enabled"] := Enabled
    SaveConfig()
    UpdateTrayIcon()
    BuildTrayMenu()
    try TrayTip Enabled ? "Enabled" : "Disabled", APP_DISPLAY, 1
}

QuitHotkeyHandler(*) {
    Log("quit via hotkey")
    ExitApp
}

; =============================================================================
; Config file watcher
; =============================================================================
WatchConfigFile() {
    global ConfigMTime
    if !FileExist(CONFIG_PATH)
        return
    mtime := FileGetTime(CONFIG_PATH, "M")
    if mtime != ConfigMTime {
        ConfigMTime := mtime
        Log("config changed on disk, reloading")
        Reload
    }
}

; =============================================================================
; Scheduled Task (autostart)
; =============================================================================
IsTaskRegistered() {
    exit := RunWait('schtasks.exe /Query /TN "' TASK_NAME '"', , "Hide")
    return exit = 0
}

RegisterTask() {
    exit := DoRegisterTask()
    if exit != 0
        MsgBox "Could not create autostart task.`nExit code: " exit
            . "`n`nTry running the utility as administrator.", APP_DISPLAY, "Icon!"
}

DoRegisterTask() {
    exe := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
    arg := A_IsCompiled ? "" : ' "' A_ScriptFullPath '"'
    xml := BuildTaskXml(exe, arg)
    xmlPath := A_Temp "\" TASK_NAME ".xml"
    try FileDelete xmlPath
    FileAppend xml, xmlPath, "UTF-16"
    cmd := 'schtasks.exe /Create /F /TN "' TASK_NAME '" /XML "' xmlPath '"'
    exit := RunWait(cmd, , "Hide")
    try FileDelete xmlPath
    return exit
}

UnregisterTask() {
    RunWait 'schtasks.exe /Delete /F /TN "' TASK_NAME '"', , "Hide"
}

BuildTaskXml(exe, arg) {
    user := EnvGet("USERDOMAIN") "\" EnvGet("USERNAME")
    argsXml := (arg != "") ? "      <Arguments>" arg "</Arguments>`n" : ""
    xml := '<?xml version="1.0" encoding="UTF-16"?>' . "`n"
    xml .= '<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">' . "`n"
    xml .= "  <RegistrationInfo>`n"
    xml .= "    <Description>" APP_DISPLAY " autostart</Description>`n"
    xml .= "  </RegistrationInfo>`n"
    xml .= "  <Triggers>`n"
    xml .= "    <LogonTrigger>`n"
    xml .= "      <Enabled>true</Enabled>`n"
    xml .= "      <UserId>" user "</UserId>`n"
    xml .= "    </LogonTrigger>`n"
    xml .= "  </Triggers>`n"
    xml .= "  <Principals>`n"
    xml .= '    <Principal id="Author">' . "`n"
    xml .= "      <UserId>" user "</UserId>`n"
    xml .= "      <LogonType>InteractiveToken</LogonType>`n"
    xml .= "      <RunLevel>HighestAvailable</RunLevel>`n"
    xml .= "    </Principal>`n"
    xml .= "  </Principals>`n"
    xml .= "  <Settings>`n"
    xml .= "    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>`n"
    xml .= "    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>`n"
    xml .= "    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>`n"
    xml .= "    <AllowHardTerminate>true</AllowHardTerminate>`n"
    xml .= "    <StartWhenAvailable>true</StartWhenAvailable>`n"
    xml .= "    <RunOnlyIfNetworkAvailable>false</RunOnlyIfNetworkAvailable>`n"
    xml .= "    <IdleSettings>`n"
    xml .= "      <StopOnIdleEnd>false</StopOnIdleEnd>`n"
    xml .= "      <RestartOnIdle>false</RestartOnIdle>`n"
    xml .= "    </IdleSettings>`n"
    xml .= "    <AllowStartOnDemand>true</AllowStartOnDemand>`n"
    xml .= "    <Enabled>true</Enabled>`n"
    xml .= "    <Hidden>false</Hidden>`n"
    xml .= "    <RunOnlyIfIdle>false</RunOnlyIfIdle>`n"
    xml .= "    <WakeToRun>false</WakeToRun>`n"
    xml .= "    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>`n"
    xml .= "    <Priority>7</Priority>`n"
    xml .= "  </Settings>`n"
    xml .= '  <Actions Context="Author">' . "`n"
    xml .= "    <Exec>`n"
    xml .= "      <Command>" exe "</Command>`n"
    xml .= argsXml
    xml .= "      <WorkingDirectory>" A_ScriptDir "</WorkingDirectory>`n"
    xml .= "    </Exec>`n"
    xml .= "  </Actions>`n"
    xml .= "</Task>`n"
    return xml
}
