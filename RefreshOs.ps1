<#
.SYNOPSIS
    RefreshOs
.DESCRIPTION
    Downloading and installing all required Software and Driver Updates
.NOTES
    2026-10-01 Created
#>

param(
    [switch] $AutoReboot,
    [int] $AutoRebootDelayInSeconds = 20
)

function Add-LogEntry {
    param([string]$Message)

    $M = "{0} | {1}" -f ((Get-Date).ToString(("yyyy.MM.dd HH:mm:ss.ffff"))), $Message

    Write-Host -Object $M
    Add-Content -Path $Script:LogFile -Value $M -Encoding utf8
}

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
    Add-LogEntry -Message "    Install result: $($Results.ResultCode) ($($Results.HResult))"

    if ($Result.RebootRequired) {
        $script:needReboot = $true
    }
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
Add-LogEntry -Message "==== "

$script:WuSession = New-Object -ComObject Microsoft.Update.Session
$script:WuSession.ClientApplicationID = $Script:Name

# Queries
$SwQuery = "IsInstalled=0 and IsHidden=0 and Type='Software'"
$DrvQuery = "IsInstalled=0 and IsHidden=0 and Type='Driver'"

# Update Collections
$SwUpdates = New-Object -ComObject Microsoft.Update.UpdateColl
$DrvUpdates = New-Object -ComObject Microsoft.Update.UpdateColl

# software updates
$SwQuery | ForEach-Object {

    Add-LogEntry -Message "Getting updates: $_ ..."        
    try {
        $Searcher = $WuSession.CreateupdateSearcher()
        $Searcher.Online = $true

        $Searcher.Search($_).Updates | ForEach-Object {
            if (!$_.EulaAccepted) { $_.AcceptEula() }
            $featureUpdate = $_.Categories | Where-Object { $_.CategoryID -eq "3689BDC8-B205-4AF4-8D4A-A63924C5E9D5" }
            if ($featureUpdate) {
                Add-LogEntry -Message "Skipping feature update: $($_.Title)"
            }
            elseif ($_.Title -match "Preview") { 
                Add-LogEntry -Message "Skipping preview update: $($_.Title)"
            }
            else {
                [void]$SwUpdates.Add($_)
            }
        }
    }
    catch {
        # If this script is running during specialize, error 8024004A will happen:
        # 8024004A	Windows Update agent operations are not available while OS setup is running.
        Add-LogEntry "Unable to search for updates: $_"
    }

}

if ($SwUpdates.Count -gt 0) {
    Add-LogEntry -Message "$($SwUpdates.Count) Software Updates found."
}
else {
    Add-LogEntry -Message "No Software Updates found."
}


# driver updates
$DrvQuery | ForEach-Object {

    Add-LogEntry -Message "Getting updates: $_ ..."        
    try {
        $Searcher = $WuSession.CreateupdateSearcher()
        $Searcher.Online = $true

        $Searcher.Search($_).Updates | ForEach-Object {
            if (!$_.EulaAccepted) { $_.AcceptEula() }
            $featureUpdate = $_.Categories | Where-Object { $_.CategoryID -eq "3689BDC8-B205-4AF4-8D4A-A63924C5E9D5" }
            if ($featureUpdate) {
                Add-LogEntry -Message "Skipping feature update: $($_.Title)"
            }
            elseif ($_.Title -match "Preview") { 
                Add-LogEntry -Message "Skipping preview update: $($_.Title)"
            }
            else {
                [void]$DrvUpdates.Add($_)
            }
        }
    }
    catch {
        # If this script is running during specialize, error 8024004A will happen:
        # 8024004A	Windows Update agent operations are not available while OS setup is running.
        Add-LogEntry "Unable to search for updates: $_"
    }

}

if ($DrvUpdates.Count -gt 0) {
    Add-LogEntry -Message "$($DrvUpdates.Count) Driver Updates found."
}
else {
    Add-LogEntry -Message "No Driver Updates found."
}

# check if there are any updates
if (($SwUpdates.Count -eq 0) -and ($DrvUpdates.Count -eq 0)) {
    Add-LogEntry -Message "No Updates found at all. Exit."
    Exit 0
}

# downloading and installing software updates

if ($SwUpdates.Count -gt 0) {
    Add-LogEntry -Message "Downloading and Installing Software Updates..."
    foreach ($Update in $SwUpdates) {
        Invoke-DownloadAndInstall -Update $Update
    }
}

# downloading and installing driver updates

if ($DrvUpdates.Count -gt 0) {
    Add-LogEntry -Message "Downloading and Installing Driver Updates..."
    foreach ($Update in $DrvUpdates) {
        Invoke-DownloadAndInstall -Update $Update
    }
}

if ($script:needReboot) {
    if ($AutoReboot) {
        Add-LogEntry -Message "A Reboot is required and will be done automatically in $AutoRebootDelayInSeconds seconds..."

        & "$($env:windir)\system32\shutdown.exe" /r /t 20 /c "$($Script:Name): Rebooting to complete the installation of Windows and/or Drivers Updates."
        Exit 0
    }
}    
else {
    Add-LogEntry -Message "No Reboot required. Exit."
}

Exit 0