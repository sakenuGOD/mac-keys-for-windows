#Requires -Version 5
<#
    uninstall.ps1 — удаление Mac Keys for Windows из автозапуска.
    Config и лог в %APPDATA%\mac-keys-for-windows\ остаются (удали вручную,
    если не нужны).
#>

$ErrorActionPreference = 'SilentlyContinue'

$TaskName = 'MacKeysForWindows'
$AppId    = 'mac-keys-for-windows'

Write-Host '== Mac Keys for Windows — удаление ==' -ForegroundColor Cyan

Get-Process -Name 'mac-keys','AutoHotkey' -ErrorAction SilentlyContinue |
    Where-Object { $_.Path -and $_.Path -match 'mac-keys' } |
    ForEach-Object {
        Write-Host "[+] Останавливаю процесс PID $($_.Id)"
        Stop-Process -Id $_.Id -Force
    }

if (Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false
    Write-Host "[+] Задача '$TaskName' удалена." -ForegroundColor Green
} else {
    Write-Host "[=] Задача '$TaskName' не найдена."
}

$dir = Join-Path $env:APPDATA $AppId
Write-Host ''
Write-Host "Config и лог не тронуты: $dir"
Write-Host "Удалить руками, если не нужны:  Remove-Item -Recurse '$dir'"
