#Requires -Version 5
<#
    install.ps1 — регистрация Mac Keys for Windows в автозапуске.
    Запуск: ПКМ по файлу → "Run with PowerShell" (либо в терминале:
            powershell -ExecutionPolicy Bypass -File .\install.ps1).
    Создаёт Scheduled Task, который стартует утилиту при входе в систему
    с повышенными правами (чтобы хоткеи работали и в elevated-окнах).
#>

$ErrorActionPreference = 'Stop'

$AppId       = 'mac-keys-for-windows'
$TaskName    = 'MacKeysForWindows'
$ScriptDir   = Split-Path -Parent $MyInvocation.MyCommand.Path
$ExePath     = Join-Path $ScriptDir 'mac-keys.exe'
$AhkPath     = Join-Path $ScriptDir 'mac-keys.ahk'
$ConfigSrc   = Join-Path $ScriptDir 'config.default.json'
$ConfigDstDir = Join-Path $env:APPDATA $AppId
$ConfigDst   = Join-Path $ConfigDstDir 'config.json'

Write-Host '== Mac Keys for Windows — установка ==' -ForegroundColor Cyan

if (-not (Test-Path $ConfigDstDir)) {
    New-Item -ItemType Directory -Force -Path $ConfigDstDir | Out-Null
}
if (-not (Test-Path $ConfigDst)) {
    Copy-Item $ConfigSrc $ConfigDst
    Write-Host "[+] Скопирован config → $ConfigDst"
} else {
    Write-Host "[=] Config уже существует, не трогаю: $ConfigDst"
}

if (Test-Path $ExePath) {
    $target  = $ExePath
    $argsStr = ''
    Write-Host "[+] Использую скомпилированный exe: $ExePath"
} elseif (Test-Path $AhkPath) {
    $ahk = Get-Command 'AutoHotkey.exe' -ErrorAction SilentlyContinue
    if (-not $ahk) {
        $candidates = @(
            "$env:ProgramFiles\AutoHotkey\v2\AutoHotkey.exe",
            "$env:ProgramFiles\AutoHotkey\AutoHotkey.exe",
            "${env:ProgramFiles(x86)}\AutoHotkey\v2\AutoHotkey.exe"
        )
        $ahk = $candidates | Where-Object { Test-Path $_ } | Select-Object -First 1
    } else {
        $ahk = $ahk.Source
    }
    if (-not $ahk) {
        Write-Host "[!] AutoHotkey v2 не найден и нет скомпилированного mac-keys.exe." -ForegroundColor Red
        Write-Host "    Поставь AHK v2: https://www.autohotkey.com/ и повтори установку."
        exit 1
    }
    $target  = $ahk
    $argsStr = "`"$AhkPath`""
    Write-Host "[+] Использую AutoHotkey: $ahk + $AhkPath"
} else {
    Write-Host '[!] Не найден ни mac-keys.exe, ни mac-keys.ahk рядом со скриптом.' -ForegroundColor Red
    exit 1
}

$action    = New-ScheduledTaskAction -Execute $target -Argument $argsStr -WorkingDirectory $ScriptDir
$trigger   = New-ScheduledTaskTrigger -AtLogOn -User "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries `
                                          -StartWhenAvailable -ExecutionTimeLimit ([TimeSpan]::Zero) `
                                          -MultipleInstances IgnoreNew

try {
    Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger `
                           -Principal $principal -Settings $settings -Force | Out-Null
    Write-Host "[+] Задача '$TaskName' зарегистрирована (запуск при входе, с повышенными правами)." -ForegroundColor Green
} catch {
    Write-Host "[!] Не удалось создать задачу: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "    Попробуй запустить PowerShell от администратора и повторить."
    exit 1
}

Write-Host ''
Write-Host 'Запускаю утилиту сейчас...'
try {
    Start-ScheduledTask -TaskName $TaskName
    Write-Host '[+] Готово. Иконка должна появиться в трее.' -ForegroundColor Green
} catch {
    Write-Host "[!] Не удалось запустить задачу: $($_.Exception.Message)" -ForegroundColor Yellow
    Write-Host "    Можно запустить вручную: $target $argsStr"
}

Write-Host ''
Write-Host "Config: $ConfigDst"
Write-Host "Master toggle: Ctrl+Alt+Shift+M  (меняется в config)"
