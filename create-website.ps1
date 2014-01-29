<#
.Synopsis
    Create website under IIS on a remote host.
.Description
    Create a website and its Application Pool. Set properties of both.
.Parameter site
    Defines the display name (in IIS Manager) of the website.
    Mandatory parameter
.Parameter port
    Defines the listening port for the website.
    Default is 80.
.Parameter appPool
    Defines the name of the application pool to associate with the site. Will be created if it does not exist.
    Default is to match the site name.
.Parameter appPath
    Defines the physical path to the site folder on the target host.
    Default is "$env:SYSTEMDRIVE\inetpub\wwwroot\$site".
.Parameter logPath
    Defines the physical path to the site folder on the target host.
    Default is "$env:SYSTEMDRIVE\inetpub\logs\$site".
.Parameter header
    Defines the host header binding that the website will respond to.
    Default is "*".
.Parameter runtime
    Defines the Managed Runtime to be used for the ApplicationPool.
    Possible values are "v1.1", "v2.0" or "v4.0".
    Default is "v4.0".
.Parameter pipeline
    Defines the Managed Pipeline Mode to be used for the ApplicationPool.
    Possible values are "Classic" or "Integrated".
    Default is "Integrated".
.Parameter identity
    Defines the identity type to be used for the ApplicationPool.
    Possible values are
        0: LocalSystem
        1: LocalService
        2: NetworkService
        3: SpecificUser
        4: ApplicationPoolIdentity
    Default is 4 (ApplicationPoolIdentity).
.Parameter username
    Defines the username (use the form: domain\username) under which the application pool should run.
    Only needs to be set if identity is set to 3.
.Parameter password
    Defines the password for the user under which the application pool should run.
    Only needs to be set if identity is set to 3.
.Parameter remove
    If this parameter is set, site will be deleted rather than created.
    Default value is $false.
.Parameter computerName
    Defines the name of the computer which will host the site.
    Default is the local computer on which the script is run.
.Notes
    Based on the work of Fabrice ZERROUKI - fabricezerrouki@hotmail.com.
    http://www.zerrouki.com/create-website/
.Example
    PS>.\create-website.ps1 -site TESTSITE
    Creates a website named 'TESTSITE', listening on the TCP80 port (default value), responding to 'http://*' (default value). The associated ApplicationPool 'TESTSITE' running with the identity 'ApplicationPoolIdentity' (default value), v4.0 .NET Framework managed runtime (default value) and 'Integrated' managed pipeline mode (default value).
.Example
    PS>.\create-website.ps1 -site TESTSITE -port 8080 -runtime v4.0 -pipeline Classic
    Creates a website named 'TESTSITE', listening on the TCP8080 port, responding to 'http://*' (default value). The associated ApplicationPool 'TESTSITE' running with the identity 'ApplicationPoolIdentity' (default value), v4.0 .NET Framework managed runtime and 'Classic' managed pipeline mode.
#>
param (
    [Parameter(Mandatory = $true)]
    [string] $site,

    [int] $port = 80,

    [string] $appPool = $site,

    [string] $appPath = ("{0}\inetpub\wwwroot\{1}" -f $env:SYSTEMDRIVE, $site.Replace(' ', '_')),

    [string] $logPath = ("{0}\inetpub\logs\{1}" -f $env:SYSTEMDRIVE, $site.Replace(' ', '_')),

    [ValidatePattern("([\w-]+\.)+[\w-]+(/[\w- ;,./?%&=]*)?")]
    [string] $header = "*",

    [ValidateSet("v1.1", "v2.0", "v4.0")]
    [string] $runtime = "v4.0",

    [ValidateSet("Classic", "Integrated")]
    [string] $pipeline = "Integrated",

    [ValidateSet(0, 1, 2, 3, 4)]
    [int] $identity = 4,

    [string] $username = $null,

    [string] $password = $null,

    [switch] $remove = $false,

    [string] $computerName = ("{0}.{1}" -f $env:COMPUTERNAME.ToLower(), $env:USERDNSDOMAIN.ToLower())
)
Invoke-Command -ComputerName $computerName -Script {
    param (
        [string] $site,
        [int] $port,
        [string] $appPool,
        [string] $appPath,
        [string] $logPath,
        [string] $header,
        [string] $runtime,
        [string] $pipeline,
        [int] $identity,
        [string] $username,
        [string] $password,
        [bool] $remove
    )
    Write-Host ("`$args: $args")

    Import-Module WebAdministration -ErrorAction Stop

    if ($remove) {
        if (Test-Path ("IIS:\Sites\{0}" -f $site)) {
            Write-Host ("Stopping website: {0}." -f $site)
            Stop-Website -Name $site
        }
        if (Test-Path ("IIS:\AppPools\{0}" -f $appPool)) {
            Write-Host ("Stopping application pool: {0}." -f $appPool)
            Stop-WebAppPool -Name $appPool
        }
        if (Test-Path ("IIS:\Sites\{0}" -f $site)) {
            Write-Host ("Deleting website: {0}." -f $site)
            Remove-Website -Name $site
        } else {
            Write-Host ("Existing website not found: {0}." -f $site)
        }
        if (Test-Path ("IIS:\AppPools\{0}" -f $appPool)) {
            Write-Host ("Deleting application pool: {0}." -f $appPool)
            Remove-WebAppPool -Name $appPool
        } else {
            Write-Host ("Existing application pool not found: {0}." -f $appPool)
        }

        if (Test-Path $appPath) {
            Write-Host ("Deleting application directory: {0}." -f $appPath)
            Remove-Item -Recurse -Force -Path $appPath
        } else {
            Write-Host ("Existing application directory not found: {0}." -f $appPath)
        }

        if (Test-Path $logPath) {
            Write-Host ("Deleting log directory: {0}." -f $logPath)
            Remove-Item -Recurse -Force -Path $logPath
        } else {
            Write-Host ("Existing log directory not found: {0}." -f $logPath)
        }
        return
    }

    if (!(Test-Path $appPath)) {
        Write-Host ("Creating application directory: {0}." -f $appPath)
        New-Item -ItemType Directory -Path $appPath
    } else {
        Write-Host ("Existing application directory found: {0}." -f $appPath)
    }

    if (!(Test-Path $logPath)) {
        Write-Host ("Creating log directory: {0}." -f $logPath)
        New-Item -ItemType Directory -Path $logPath
    } else {
        Write-Host ("Existing log directory found: {0}." -f $logPath)
    }

    if (!(Test-Path ("IIS:\AppPools\{0}" -f $appPool))) {
        Write-Host ("Creating application pool: {0}." -f $appPool)
        New-WebAppPool -Name $appPool -Force | Format-Table
    } else {
        Write-Host ("Existing application pool found: {0}." -f $appPool)
    }
    Write-Host ("Setting application pool properties. runtime: {0}, pipeline: {1}, identity: {2}." -f $runtime, $pipeline, $identity)
    Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name managedRuntimeVersion -Value $runtime
    if ($pipeline -eq "Integrated") {
        Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name managedPipelineMode -Value 0
    } else {
        Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name managedPipelineMode -Value 1
    }
    Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name processModel.identityType -Value $identity
    if (($username -ne $null) -and ($password -ne $null)) {
        Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name processModel.username -Value $username
        Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name processModel.password -Value $password
        Set-ItemProperty ("IIS:\AppPools\{0}" -f $appPool) -Name processModel.identityType -Value 3
    }

    if (!(Test-Path ("IIS:\Sites\{0}" -f $site))) {
        Write-Host ("Creating website: {0}." -f $site)
        New-Website -Name $site -Port $port -HostHeader $header -PhysicalPath $appPath -ApplicationPool $appPool -Force | Format-Table
    } else {
        Write-Host ("Existing website found: {0}." -f $site)
    }

    Write-Host ("Setting website bindings. header: {0}, port: {1}." -f $header, $port)
    Set-WebBinding -Name $site -BindingInformation ("{0}:{1}:" -f $header, $port) -PropertyName Port -Value $port

    Write-Host ("Setting website properties. physicalPath: {0}, applicationPool: {1}, logPath: {2}." -f $appPath, $appPool, $logPath)
    Set-ItemProperty ("IIS:\Sites\{0}" -f $site) -Name physicalPath -Value $appPath
    Set-ItemProperty ("IIS:\Sites\{0}" -f $site) -Name applicationPool -Value $appPool
    Set-ItemProperty ("IIS:\Sites\{0}" -f $site) -Name logfile.directory -Value $logPath

    Write-Host ("Starting website: {0}." -f $site)
    Start-Website -Name $appPool

    Write-Host ("Restarting application pool: {0}." -f $appPool)
    Restart-WebAppPool -Name $appPool
} -ArgumentList $site, $port, $appPool, $appPath, $logPath, $header, $runtime, $pipeline, $identity, $username, $password, $remove