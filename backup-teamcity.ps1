<#
.Synopsis
    Trigger a TeamCity backup using the TeamCity REST API.
.Parameter username
    Defines a TeamCity username which has authority to trigger backups.
.Parameter password
    Defines the password for the user which will trigger the backup.
.Parameter baseUrl
    Defines the URL to the TeamCity server (eg: http://teamcity.example.com).
    If not set, the script will attempt to determine it from the TeamCity properties file (when run as a teamcity job).
.Parameter dataPath
    Defines the folder path to the TeamCity data directory on the TeamCity server (eg: c:\ProgramData\TeamCity).
    If not set, the script will attempt to determine it from the TeamCity properties file.
.Parameter sleep
    Defines the time in seconds between polling of the TeamCity API to check if the backup has completed.
    Defaults to 10 seconds.
.Parameter timeout
    Defines the time in seconds before the build job will give up waiting for the backup to complete.
    Defaults to 600 seconds.
.Parameter debug
    If set, will output some more verbose messaging about script progress.
    Defaults to false.
.Example
 - Create a TeamCity build configuration.
 - Set this gist as the VCS root, use anonymous access (https://gist.github.com/8302320.git or fork your own).
 - Add a Powershell build step which calls teamcity-backup.ps1, pass a script parameter of "-debug" if you want the debug output in the logs.
 - Create a build parameter (Name: tc_username) and populate with the username of a TC user with backup rights
 - Create a build parameter (Name: tc_password, Spec: password display='hidden') and populate with the tc user password
 - Add a shedule (or other) trigger to perform regular backups (eg: Cron command: 0 0 20 * * 2,3,4,5,6 *).
.Example
    Command line usage:
    PS> .\tc-backup.ps1 -username "foo" -password "bar" -baseUrl "http://teamcity:8111"
.Notes
    If server returns 401 errors, ensure Basic Auth authentication scheme is enabled in TeamCity admin settings.
#>
param(
    [string] $username = $env:tc_username,
    [string] $password = $env:tc_password,
    [string] $baseUrl,
    [string] $dataPath,
    [int] $sleep = 10,
    [int] $timeout = 600,
    [switch] $debug = $false
)

if ($debug) { $debugPreference = 'Continue' }

Write-Debug ("TEAMCITY_BUILD_PROPERTIES_FILE: {0}" -f $env:TEAMCITY_BUILD_PROPERTIES_FILE)
if((!$baseUrl -or !$username -or !$password) -and (Test-Path -path $env:TEAMCITY_BUILD_PROPERTIES_FILE)) {
    $tcConfigPropertiesFile = "{0}.xml" -f (((Select-String -path $env:TEAMCITY_BUILD_PROPERTIES_FILE -pattern "teamcity.configuration.properties.file")[0] -split "=", 2)[1]).Replace("\\", "\").Replace("\:", ":")
    Write-Debug ("Loading TeamCity config properties from: {0}" -f $tcConfigPropertiesFile)
    $xml = New-Object System.Xml.XmlDocument
    $xml.XmlResolver = $null
    $xml.Load((Resolve-Path $tcConfigPropertiesFile).Path)
    if (!$baseUrl) {
        $baseUrl = $xml.SelectSingleNode("//entry[@key = 'teamcity.serverUrl']").'#text'
    }
    if (!$username) {
        $username = $xml.SelectSingleNode("//entry[@key = 'tc_username']").'#text'
    }
    if (!$password) {
        $password = $xml.SelectSingleNode("//entry[@key = 'tc_password']").'#text'
    }
}
if($baseUrl -and !$dataPath){
    $dataPath = [Microsoft.Win32.RegistryKey]::OpenRemoteBaseKey("LocalMachine", ([System.Uri] $baseUrl).Host).OpenSubKey("System\CurrentControlSet\Control\Session manager\Environment").GetValue("TEAMCITY_DATA_PATH")
    Write-Debug ("dataPath (.Net ORBK): {0}" -f $dataPath)
}
Write-Debug ("username: {0}" -f $username)
Write-Debug ("baseUrl: {0}" -f $baseUrl)
Write-Debug ("dataPath: {0}" -f $dataPath)
Write-Debug ("sleep: {0}" -f $sleep)
Write-Debug ("timeout: {0}" -f $timeout)


if(!$baseUrl){
    Write-Host "Failed to determine base URL."
    exit
}
if(!$dataPath){
    Write-Host "Failed to determine data path."
    exit
}

function Execute-TeamCityBackup {
    param(
        [string] $baseUrl,
        [string] $username,
        [string] $password,
        [string] $filenamePrefix = "TeamCity_Backup_",
        [string] $addTimestamp = $true,
        [string] $includeConfigs = $true,
        [string] $includeDatabase = $true,
        [string] $includeBuildLogs = $true, # change to false if the (very large) build log history is not required.
        [string] $includePersonalChanges = $true
    )
    $url = [System.String]::Format("{0}/httpAuth/app/rest/server/backup?addTimestamp={1}&includeConfigs={2}&includeDatabase={3}&includeBuildLogs={4}&includePersonalChanges={5}&fileName={6}",
        $baseUrl,
        $addTimestamp,
        $includeConfigs,
        $includeDatabase,
        $includeBuildLogs,
        $includePersonalChanges,
        $filenamePrefix)
    return Get-WebResponse -url $url -username $username -password $password -method "POST"
}
function Get-TeamCityBackupStatus {
    param(
        [string] $baseUrl,
        [string] $username,
        [string] $password
    )
    $url = "{0}/httpAuth/app/rest/server/backup" -f $baseUrl
    return Get-WebResponse -url $url -username $username -password $password
}
function Get-WebResponse {
    param(
        [string] $url,
        [string] $username,
        [string] $password,
        [string] $method = "GET"
    )
    $webrequest = [System.Net.WebRequest]::Create($url)
    $webRequest.Method = $method
    $webrequest.PreAuthenticate = $true
    $webrequest.Credentials = New-Object System.Net.NetworkCredential($username, $password)
    return ([System.IO.StreamReader]($webrequest.GetResponse().GetResponseStream())).ReadToEnd()
}
function Convert-DateString {
    param(
        [string] $date,
        [string[]] $format = "yyyyMMdd_HHmmss"
    )
    $result = New-Object DateTime
    if (([DateTime]::TryParseExact($date, $format, [System.Globalization.CultureInfo]::InvariantCulture, [System.Globalization.DateTimeStyles]::None, [ref] $result))) {
        return $result
    }
    return $null
}
function Purge-Backups {
    param (
        [string] $folder,
        [string] $filenamePrefix = "TeamCity_Backup_"
    )
    Write-Host ("Purging backups from folder: {0}." -f $folder)
    Get-ChildItem $folder -filter ("{0}*.zip" -f $filenamePrefix) | Where-Object { ((Is-PurgeCandidate $_.Name $filenamePrefix)) } | % {
        Remove-Item $_.FullName
    }
}
function Is-PurgeCandidate {
    param (
        [string] $backupFile,
        [string] $filenamePrefix
    )
    $backupDate = (Convert-DateString ($backupFile.Replace($filenamePrefix, "").Replace(".zip", "")))
    if($backupDate -gt (Get-Date).Date.AddDays(-14)) {
        Write-Debug ("{0} will be retained. Rule: Taken within last 14 days." -f $backupFile)
        return $false
    }
    if($backupDate.Day -eq 1) {
        Write-Debug ("{0} will be retained. Rule: Taken on the first of the month." -f $backupFile)
        return $false
    }
    Write-Debug ("{0} will be purged." -f $backupFile)
    return $true
}
Write-Host ("Triggering backup.")
$backupFilename = Execute-TeamCityBackup -baseUrl $baseUrl -username $username -password $password
Write-Host ("Backup filename: {0}." -f $backupFilename)
#Write-Host ("##teamcity[setParameter name='backupFilename' value='{0}']" -f $backupFilename)
$status = ""
$timeoutTimespan = New-Timespan -Seconds $timeout
$stopwatch = [diagnostics.stopwatch]::StartNew()
while (($status -ne "Idle") -and ($stopwatch.elapsed -lt $timeoutTimespan)) {
    $status = Get-TeamCityBackupStatus -baseUrl $baseUrl -username $username -password $password
    Write-Host ("Backup status: {0}" -f $status)
    if ($status -ne "Idle"){
        Start-Sleep -Seconds $sleep
    }
}
$backupFolder = ("\\{0}\{1}\backup" -f ([System.Uri] $baseUrl).Host, $dataPath.Replace(":", "$"))
if ($status -eq "Idle") {
    Write-Host ("Backup complete.")
    $backupFilePath = ("{0}\{1}" -f $backupFolder, $backupFilename)
    if (Test-Path -path $backupFilePath) {
        Write-Host ("Backup saved to: {0}" -f $backupFilePath)
        Write-Host ("##teamcity[setParameter name='backupFilePath' value='{0}']" -f $backupFilePath)
    } else {
        Write-Host ("Failed to determine backup file location.")
        Write-Host ("Backup should have saved to: {0}" -f $backupFilePath)
    }
}
elseif (($status -ne "Idle") -and ($stopwatch.elapsed -gt $timeout)) {
    Write-Host ("Backup execution exceeded script timeout value of: {0} seconds." -f $timeout)
    Write-Host ("Backup may still be in progress.")
}
Purge-Backups $backupFolder