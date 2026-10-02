#requires -Version 5.1
#requires -RunAsAdministrator

<#
.SYNOPSIS
    RefreshOs
.DESCRIPTION
    Downloading and installing all required Software and Driver Updates
    Credits to https://github.com/mtniehaus/UpdateOS
.NOTES
    2026-10-01 Created
#>

param(
    [switch] $AutoReboot,
    [int] $AutoRebootDelayInSeconds = 20
)

# check admin rights
function Test-IsElevated {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

# write log text to console and file
function Add-LogEntry {
    param([string]$Message)

    $M = "{0} | {1}" -f ((Get-Date).ToString(("yyyy.MM.dd HH:mm:ss.ffff"))), $Message

    Write-Host -Object $M
    Add-Content -Path $Script:LogFile -Value $M -Encoding utf8
}

# download and install a single update
function Invoke-DownloadAndInstall {
    param($Update)

    $SingleUpdate = New-Object -ComObject Microsoft.Update.UpdateColl
    $SingleUpdate.Add($Update) | Out-Null
    
    $WuDownloader = $script:WuSession.CreateUpdateDownloader()
    $WuDownloader.Updates = $SingleUpdate
    
    $WuInstaller = $script:WuSession.CreateUpdateInstaller()
    $WuInstaller.Updates = $SingleUpdate
    $WuInstaller.ForceQuiet = $true
    
    Add-LogEntry -Message "  Downloading update: $($Update.Title)"
    $Download = $WuDownloader.Download()
    Add-LogEntry -Message "    Download result: $($Download.ResultCode) ($($Download.HResult))"
    
    Add-LogEntry -Message "  Installing update: $($Update.Title)"
    $Result = $WuInstaller.Install()
    Add-LogEntry -Message "    Install result: $($Result.ResultCode) ($($Result.HResult))"

    if ($Result.RebootRequired) {
        $script:RebootRequired = $true
    }
}

# check admin
if (-not (Test-IsElevated)) {
    throw 'Admin Rights required.'
}

# script version
$script:Version = "1.0"

# script name
$Script:Name = $MyInvocation.MyCommand.Name -replace '.ps1', ''

# path to logfile
$script:LogFile = "$($env:ProgramData)\$($Script:Name)\$($Script:Name).log"

# create logfile, if not exists
if (-not (Test-Path -Path $script:LogFile)) {
    $null = New-Item -Path $Script:LogFile -ItemType File -Force
    Add-LogEntry -Message "'$($script:LogFile)' created."
}

# update types
$UpdateTypes = @(
    @{
        Name  = "Software"
        Query = "IsInstalled=0 and IsHidden=0 and Type='Software'"
        Updates = New-Object -ComObject Microsoft.Update.UpdateColl
    },
    @{
        Name  = "Driver"
        Query = "IsInstalled=0 and IsHidden=0 and Type='Driver'"
        Updates = New-Object -ComObject Microsoft.Update.UpdateColl
    }
)

# logfile header infos
$ComputerName = $env:ComputerName
$SerialNo = "0"
$WindowsVersion = "0"

try {
    $OsVersion = [Environment]::OSVersion.Version
    $WindowsVersion = "{0}.{1}.{2}" -f $OsVersion.Major, $OsVersion.Minor, $OsVersion.Build

    if ((Get-ItemProperty -Path "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").PSObject.Properties.Name -contains "UBR") {
        $UBR = (Get-Item "HKLM:SOFTWARE\Microsoft\Windows NT\CurrentVersion").GetValue('UBR')
        $WindowsVersion += ".$UBR"
    }
}
catch {}

try {
    $SerialNo = (Get-CimInstance -ClassName win32_bios).SerialNumber
}
catch {}


Add-LogEntry -Message "==== $($Script:Name) v$($script:Version) started ===="
Add-LogEntry -Message "NAME: $ComputerName"
Add-LogEntry -Message "SERIAL-NUMBER: $SerialNo"
Add-LogEntry -Message "WINDOWS-VERSION: $WindowsVersion"

if ($AutoReboot) { 
    $M = "Auto Reboot enabled. Timeout $($AutoRebootDelayInSeconds) seconds." 
} 
else { 
    $M = "Not Auto Reboot." 
}

Add-LogEntry -Message "==== $($M) ===="

$script:WuSession = New-Object -ComObject Microsoft.Update.Session
$script:WuSession.ClientApplicationID = $Script:Name

# handling the different update types
foreach ($UpdateType in $UpdateTypes) {
    Add-LogEntry -Message "Getting [$($UpdateType.Name)] Updates ..."        
    try {
        $Searcher = $WuSession.CreateupdateSearcher()
        $Searcher.Online = $true

        $Searcher.Search($UpdateType.Query).Updates | ForEach-Object {
            if (!$_.EulaAccepted) { $_.AcceptEula() }
            $featureUpdate = $_.Categories | Where-Object { $_.CategoryID -eq "3689BDC8-B205-4AF4-8D4A-A63924C5E9D5" }
            if ($featureUpdate) {
                Add-LogEntry -Message "  Skipping feature update: $($_.Title)"
            }
            elseif ($_.Title -match "Preview") { 
                Add-LogEntry -Message "  Skipping preview update: $($_.Title)"
            }
            else {
                [void]$UpdateType.Updates.Add($_)
            }
        }
    }
    catch {
        Add-LogEntry "  Error searching for Updates: $_"
    }

    if ($UpdateType.Updates.Count -gt 0) {
        Add-LogEntry -Message "  $($UpdateType.Updates.Count) Updates found."
    }
    else {
        Add-LogEntry -Message "  No Updates found."
    }
}


# Queries
# $SwQuery = "IsInstalled=0 and IsHidden=0 and Type='Software'"
# $DrvQuery = "IsInstalled=0 and IsHidden=0 and Type='Driver'"

# # Update Collections
# $SwUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
# $DrvUpdates = New-Object -ComObject Microsoft.Update.UpdateColl

# # software updates
# $SwQuery | ForEach-Object {

#     Add-LogEntry -Message "Getting updates: $_ ..."        
#     try {
#         $Searcher = $WuSession.CreateupdateSearcher()
#         $Searcher.Online = $true

#         $Searcher.Search($_).Updates | ForEach-Object {
#             if (!$_.EulaAccepted) { $_.AcceptEula() }
#             $featureUpdate = $_.Categories | Where-Object { $_.CategoryID -eq "3689BDC8-B205-4AF4-8D4A-A63924C5E9D5" }
#             if ($featureUpdate) {
#                 Add-LogEntry -Message "Skipping feature update: $($_.Title)"
#             }
#             elseif ($_.Title -match "Preview") { 
#                 Add-LogEntry -Message "Skipping preview update: $($_.Title)"
#             }
#             else {
#                 [void]$SwUpdates.Add($_)
#             }
#         }
#     }
#     catch {
#         # If this script is running during specialize, error 8024004A will happen:
#         # 8024004A	Windows Update agent operations are not available while OS setup is running.
#         Add-LogEntry "Unable to search for updates: $_"
#     }

# }

# if ($SwUpdates.Count -gt 0) {
#     Add-LogEntry -Message "$($SwUpdates.Count) Software Updates found."
# }
# else {
#     Add-LogEntry -Message "No Software Updates found."
# }


# # driver updates
# $DrvQuery | ForEach-Object {

#     Add-LogEntry -Message "Getting updates: $_ ..."        
#     try {
#         $Searcher = $WuSession.CreateupdateSearcher()
#         $Searcher.Online = $true

#         $Searcher.Search($_).Updates | ForEach-Object {
#             if (!$_.EulaAccepted) { $_.AcceptEula() }
#             $featureUpdate = $_.Categories | Where-Object { $_.CategoryID -eq "3689BDC8-B205-4AF4-8D4A-A63924C5E9D5" }
#             if ($featureUpdate) {
#                 Add-LogEntry -Message "Skipping feature update: $($_.Title)"
#             }
#             elseif ($_.Title -match "Preview") { 
#                 Add-LogEntry -Message "Skipping preview update: $($_.Title)"
#             }
#             else {
#                 [void]$DrvUpdates.Add($_)
#             }
#         }
#     }
#     catch {
#         # If this script is running during specialize, error 8024004A will happen:
#         # 8024004A	Windows Update agent operations are not available while OS setup is running.
#         Add-LogEntry "Unable to search for updates: $_"
#     }

# }

# if ($DrvUpdates.Count -gt 0) {
#     Add-LogEntry -Message "$($DrvUpdates.Count) Driver Updates found."
# }
# else {
#     Add-LogEntry -Message "No Driver Updates found."
# }

# check if there are any updates
$TotalUpdateCount = Measure-Object -InputObject ($UpdateTypes.Updates) -Property Count
if ($null -eq $TotalUpdateCount) {
    Add-LogEntry -Message "No Updates found at all. Exit."
    Exit 0
}

# downloading and installing updates for every update type
$UpdateTypes | ForEach-Object {
    if ($null -ne $_.Updates) {
        if ($_.Updates.Count -gt 0) {
            Add-LogEntry -Message "Downloading and Installing [$($_.Name)] Updates..."
            foreach ($Update in $_.Updates) {
                Invoke-DownloadAndInstall -Update $Update
            }        
        }
    }
}

# downloading and installing software updates

# if ($SwUpdates.Count -gt 0) {
#     Add-LogEntry -Message "Downloading and Installing Software Updates..."
#     foreach ($Update in $SwUpdates) {
#         Invoke-DownloadAndInstall -Update $Update
#     }
# }

# downloading and installing driver updates

# if ($DrvUpdates.Count -gt 0) {
#     Add-LogEntry -Message "Downloading and Installing Driver Updates..."
#     foreach ($Update in $DrvUpdates) {
#         Invoke-DownloadAndInstall -Update $Update
#     }
# }

if ($script:RebootRequired) {
    if ($AutoReboot) {
        Add-LogEntry -Message "Reboot is required and will be done automatically in $AutoRebootDelayInSeconds seconds..."
        & "$($env:windir)\system32\shutdown.exe" /r /f /t $AutoRebootDelayInSeconds /d P:2:3 /c "$($Script:Name): Rebooting to complete the installation of Updates."
        Exit 0
    } else {
        Add-LogEntry -Message "Reboot is required but wasn't forced. Exit."
    }
}    
else {
    Add-LogEntry -Message "Reboot not required. Exit."
}

Exit 0