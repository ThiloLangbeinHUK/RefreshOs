@echo off
call %systemroot%\system32\windowspowershell\v1.0\powershell.exe -executionpolicy bypass -noprofile -file "%~dp0RefreshOs.ps1" -AutoReboot