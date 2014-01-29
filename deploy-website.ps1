<#
.Synopsis
    Deploy a website to IIS using MSDeploy.
.Description
    ...
.Parameter computerName
    Defines the name of the computer which will host the site.
    Default is the local computer on which the script is run.
.Parameter username
    Defines the username under which the web deployment will be run.
.Parameter password
    Defines the password for the user under which the  web deployment will be run.
.Parameter site
    Defines the display name (in IIS Manager) of the website.
    Mandatory parameter
.Parameter url
    Defines the url of the website.
    Mandatory parameter
.Parameter parameters
    Defines optional parameters (as a hashtable) for MSDeploy.
    Usage: @{ Param1Name = "Param1Value"; Param2Name = "Param2Value" }
.Notes
    ...
.Example
    PS>.\deploy-website.ps1 -site test.site -url http://localhost:8080
.Example
    PS>.\deploy-website.ps1 -computerName host.example.com -site "Default Web Site\testsite" -url "http://host.example.com/testsite"
.Example
    In TeamCity PowerShell build step, set step to 'Source Code' (to enable passing in a hashtable parameter), and add the script line below:
    & {%teamcity.build.checkoutDir%\Scripts\WebDeploy.ps1 -computerName "%site_host%" -username "%username%" -password "%password%" -package "%teamcity.build.checkoutDir%\WebDeploy\AppName.%dep.ArtifactBuild.build.number%.zip" -site "AppName" -url "http://%site_host%:%site_port%" -parameters @{"IIS Web Application Name"="AppName";"AppName-Web.config Connection String"="Integrated Security=SSPI;Persist Security Info=False;Initial Catalog=DocVault;Data Source=DBServer"}}
#>
param(
    [string] $computerName = ("{0}.{1}" -f $env:COMPUTERNAME.ToLower(), $env:USERDNSDOMAIN.ToLower()),

    [string] $username,

    [string] $password,

    [Parameter(Mandatory = $true)]
    [string] $site,

    [Parameter(Mandatory = $true)]
    [string] $url,
    
    [Parameter(Mandatory = $true)]
    [string] $package,

    [hashtable] $parameters
)
Add-PSSnapin WDeploySnapin3.0
$credential = New-Object System.Management.Automation.PSCredential ($username, (ConvertTo-SecureString $password -AsPlainText -Force))
$publishSettingsFile = ("{0}\{1}.publishsettings" -f ((Get-Item $env:TEMP).FullName), $computerName)
New-WDPublishSettings -ComputerName $computerName -Credentials $credential -AllowUntrusted -Site $site -SiteUrl $url -AgentType WMSvc -FileName $publishSettingsFile
if ($parameters) {
    Restore-WDPackage $package -DestinationPublishSettings $publishSettingsFile -Parameters $parameters
} else {
    Restore-WDPackage $package -DestinationPublishSettings $publishSettingsFile
}
Remove-Item $publishSettingsFile