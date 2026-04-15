#Requires AutoHotkey v2.0
#SingleInstance Force
#Warn All, Off

#Include lib\json.ahk

; =============================================================================
; Constants
; =============================================================================
APP_DISPLAY := "Mac Keys for Windows"
APP_ID      := "mac-keys-for-windows"
TASK_NAME   := "MacKeysForWindows"

CONFIG_DIR     := EnvGet("APPDATA") . "\" . APP_ID
CONFIG_PATH    := CONFIG_DIR . "\config.json"
LOG_PATH       := CONFIG_DIR . "\mac-keys.log"
DEFAULT_CONFIG := A_ScriptDir . "\config.default.json"

; =============================================================================
; State
; =============================================================================
global Config      := Map()
global Enabled     := true
global Paused      := false
global PauseUntil  := 0
global ConfigMTime := 0

; =============================================================================
; Entry point
; =============================================================================
Main()

Main() {
    global ConfigMTime
    EnsureConfigDir()
    EnsureDefaultConfig()
    LoadConfig()
    ConfigMTime := FileGetTime(CONFIG_PATH, "M")

    RegisterMasterToggle()
    RegisterBindings()
    BuildTrayMenu()
    UpdateTrayIcon()

    SetTimer CheckPauseExpiry, 500
    SetTimer WatchConfigFile, 2000
    Log("started")
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
        return
    if FileExist(DEFAULT_CONFIG) {
        FileCopy DEFAULT_CONFIG, CONFIG_PATH
        return
    }
    ; Embedded minimal fallback
    FileAppend '{"enabled":true,"autoPauseFullscreen":true,"masterToggleHotkey":"^!+m","excludedApps":[],"fullscreenWhitelist":[],"bindings":[]}', CONFIG_PATH, "UTF-8"
}

LoadConfig() {
    global Config
    try {
        text := FileRead(CONFIG_PATH, "UTF-8")
        Config := Json.Parse(text)
    } catch Error as e {
        MsgBox "Failed to read config.json:`n" e.Message "`n`nCheck syntax (commas, quotes). Using default config.", APP_DISPLAY, "Icon!"
        text := FileRead(DEFAULT_CONFIG, "UTF-8")
        Config := Json.Parse(text)
    }
    ; Defaults
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

    global Enabled := Config["enabled"]
}

SaveConfig() {
    global Config
    text := Json.Stringify(Config, "  ")
    try FileDelete CONFIG_PATH
    FileAppend text, CONFIG_PATH, "UTF-8"
    global ConfigMTime := FileGetTime(CONFIG_PATH, "M")
}

; =============================================================================
; Hotkey registration
; =============================================================================
RegisterMasterToggle() {
    global Config
    HotIf
    try {
        Hotkey Config["masterToggleHotkey"], MasterToggleHandler, "On"
    } catch {
        Log("failed to register master toggle: " Config["masterToggleHotkey"])
    }
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
            Hotkey from, CreateHandler(to), "On"
        } catch Error as e {
            Log("bad binding " from " -> " to ": " e.Message)
        }
    }
    HotIf
}

CreateHandler(target) {
    return (*) => SendTarget(target)
}

SendTarget(target) {
    try Send target
}

; =============================================================================
; Gate function — determines whether mac-keys hotkeys are active
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
        if (style & 0x00C00000)  ; WS_CAPTION
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
; Tray menu
; =============================================================================
BuildTrayMenu() {
    global Config, Enabled
    tray := A_TrayMenu
    tray.Delete()

    tray.Add("Enabled", ToggleEnabledMenu)
    if Enabled
        tray.Check("Enabled")
    tray.Add("Pause for 30 seconds", Pause30sMenu)
    tray.Add("Resume", UnpauseMenu)
    tray.Add()

    tray.Add("Disable in current app", DisableInCurrentAppMenu)
    tray.Add("Keep active in current app (fullscreen)", KeepActiveInCurrentAppMenu)

    excSub := Menu()
    if Config["excludedApps"].Length = 0 {
        excSub.Add("(empty)", (*) => 0)
        excSub.Disable("(empty)")
    } else {
        for app in Config["excludedApps"]
            excSub.Add(app, RemoveExcludedHandler)
    }
    tray.Add("Excluded apps", excSub)

    wlSub := Menu()
    if Config["fullscreenWhitelist"].Length = 0 {
        wlSub.Add("(empty)", (*) => 0)
        wlSub.Disable("(empty)")
    } else {
        for app in Config["fullscreenWhitelist"]
            wlSub.Add(app, RemoveWhitelistHandler)
    }
    tray.Add("Fullscreen whitelist", wlSub)

    tray.Add("Auto-pause in fullscreen", ToggleAutoPauseMenu)
    if Config["autoPauseFullscreen"]
        tray.Check("Auto-pause in fullscreen")
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

    tray.Default := "Enabled"
    tray.ClickCount := 1
}

UpdateTrayIcon() {
    global Enabled, Paused, Config
    icon := "shell32.dll"
    idx  := 44  ; enabled (check)
    if !Enabled
        idx := 132  ; disabled (x-like)
    else if Paused
        idx := 238  ; paused-ish
    try TraySetIcon icon, idx
    A_IconTip := BuildTooltip()
}

BuildTooltip() {
    global Enabled, Paused, Config
    s := APP_DISPLAY
    if !Enabled
        return s " — OFF"
    if Paused
        return s " — paused"
    return s " — ON"
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
        TrayTip "Could not detect active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("excludedApps", proc) {
        SaveConfig()
        BuildTrayMenu()
        TrayTip proc " added to excludedApps.", APP_DISPLAY, 2
    } else {
        TrayTip proc " already in list.", APP_DISPLAY, 2
    }
}

KeepActiveInCurrentAppMenu(*) {
    proc := GetActiveProcessNameLower()
    if proc = "" {
        TrayTip "Could not detect active app.", APP_DISPLAY, 2
        return
    }
    if AddToList("fullscreenWhitelist", proc) {
        SaveConfig()
        BuildTrayMenu()
        TrayTip proc " added to fullscreenWhitelist.", APP_DISPLAY, 2
    } else {
        TrayTip proc " already in list.", APP_DISPLAY, 2
    }
}

RemoveExcludedHandler(itemName, *) {
    RemoveFromList("excludedApps", itemName)
    SaveConfig()
    BuildTrayMenu()
}

RemoveWhitelistHandler(itemName, *) {
    RemoveFromList("fullscreenWhitelist", itemName)
    SaveConfig()
    BuildTrayMenu()
}

ToggleAutoPauseMenu(*) {
    global Config
    Config["autoPauseFullscreen"] := !Config["autoPauseFullscreen"]
    SaveConfig()
    BuildTrayMenu()
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
}

AboutMenu(*) {
    global Config
    MsgBox APP_DISPLAY "`n`nConfig:`n" CONFIG_PATH "`n`nLog:`n" LOG_PATH "`n`nMaster toggle: " Config["masterToggleHotkey"], APP_DISPLAY, "Icon*"
}

QuitMenu(*) {
    Log("quit")
    ExitApp
}

; =============================================================================
; Master toggle hotkey (always active, ignores context)
; =============================================================================
MasterToggleHandler(*) {
    global Enabled, Config
    Enabled := !Enabled
    Config["enabled"] := Enabled
    SaveConfig()
    UpdateTrayIcon()
    BuildTrayMenu()
    TrayTip Enabled ? "Enabled" : "Disabled", APP_DISPLAY, 1
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
    exe := A_IsCompiled ? A_ScriptFullPath : A_AhkPath
    arg := A_IsCompiled ? "" : ' "' A_ScriptFullPath '"'
    xml := BuildTaskXml(exe, arg)
    xmlPath := A_Temp "\" TASK_NAME ".xml"
    try FileDelete xmlPath
    FileAppend xml, xmlPath, "UTF-16"
    cmd := 'schtasks.exe /Create /F /TN "' TASK_NAME '" /XML "' xmlPath '"'
    exit := RunWait(cmd, , "Hide")
    try FileDelete xmlPath
    if exit != 0 {
        MsgBox "Could not create autostart task.`nExit code: " exit "`n`nTry running the utility as administrator.", APP_DISPLAY, "Icon!"
    }
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
