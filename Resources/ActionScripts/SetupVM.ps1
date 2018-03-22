

[CmdletBinding()]
param(
[parameter(Mandatory=$false, Position=1)]
[ValidateNotNullOrEmpty()] 
[string]$serverName,

[parameter(Mandatory=$True, Position=2)]
[ValidateNotNullOrEmpty()] 
[string]$username,

[parameter(Mandatory=$True, Position=3)]
[ValidateNotNullOrEmpty()] 
[string]$password,

[parameter(Mandatory=$false, Position=4)]
[ValidateNotNullOrEmpty()] 
[string]$Prompt
)
###Check to see if user is Admin

$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(`
        [Security.Principal.WindowsBuiltInRole] "Administrator")
        
if ($isAdmin -eq 'True') {


#################################################################
##DSVM Does not have SQLServer Powershell Module Install or Update 
#################################################################


Write-Host "Installing SQLServer Power Shell Module or Updating to latest "


if (Get-Module -ListAvailable -Name SQLServer) 
    {Update-Module -Name "SQLServer" -MaximumVersion 21.0.17199}
Else 
    {Install-Module -Name SqlServer -RequiredVersion 21.0.17199 -Scope AllUsers -AllowClobber -Force}

#Set-PSRepository -Name PSGallery -InstallationPolicy Untrusted
    Import-Module -Name SqlServer -MaximumVersion 21.0.17199 -Force



#$Prompt= if ($Prompt -match '^y(es)?$') {'Y'} else {'N'}
$Prompt = 'N'



$SolutionName = "Hospital"
$SolutionFullName = "r-server-hospital-length-of-stay" 
$JupyterNotebook = "Hospital_Length_Of_Stay_Notebook.ipynb"
$odbcName = 'CampOpt'
### DON'T FORGET TO CHANGE TO MASTER LATER...
$Branch = "master" 
$InstallPy = 'Yes' ## If Solution has a Py Version this should be 'Yes' Else 'No'
$SampleWeb = 'Yes' ## If Solution has a Sample Website  this should be 'Yes' Else 'No'  
$setupLog = "c:\tmp\$SolutionName_setup_log.txt"
$isDsvm = if(Test-Path "C:\dsvm") {"Yes"} else {"No"}


Start-Transcript -Path $setupLog -Append
$startTime = Get-Date
Write-Host "Start time:" $startTime 
Write-Host "ServerName set to $ServerName"



$solutionTemplateName = "Solutions"
$solutionTemplatePath = "C:\" + $solutionTemplateName
$checkoutDir = $SolutionName
$SolutionPath = $solutionTemplatePath + '\' + $checkoutDir
$desktop = "C:\Users\Public\Desktop\"
$scriptPath = $SolutionPath + "\Resources\ActionScripts\"
$SolutionData = $SolutionPath + "\Data\"



##########################################################################
#Clone Data from GIT
##########################################################################


$clone = "git clone --branch $Branch --single-branch https://github.com/Microsoft/$SolutionFullName $solutionPath"

if (Test-Path $SolutionPath) { Write-Host "Solution has already been cloned"}
ELSE {Invoke-Expression $clone}




############################################################################################
#Configure SQL to Run our Solutions 
############################################################################################

#Write-Host -ForegroundColor 'Cyan' " Switching SQL Server to Mixed Mode"
    if([string]::IsNullOrEmpty($serverName))   
    {$Query = "SELECT SERVERPROPERTY('ServerName')"
    $si = Invoke-Sqlcmd  -Query $Query
    $si = $si.Item(0)}
    else 
    {$si = $serverName}
    $serverName = $si

    Write-Host "Servername set to $serverName"


### Change Authentication From Windows Auth to Mixed Mode 
Invoke-Sqlcmd -Query "EXEC xp_instance_regwrite N'HKEY_LOCAL_MACHINE', N'Software\Microsoft\MSSQLServer\MSSQLServer', N'LoginMode', REG_DWORD, 2;" -ServerInstance "LocalHost" 

Write-Host "Configuring SQL to allow running of External Scripts "
### Allow Running of External Scripts , this is to allow R Services to Connect to SQL
Invoke-Sqlcmd -Query "EXEC sp_configure  'external scripts enabled', 1"

### Force Change in SQL Policy on External Scripts 
Invoke-Sqlcmd -Query "RECONFIGURE WITH OVERRIDE" 
Write-Host "SQL Server Configured to allow running of External Scripts "

Write-Host "Restarting SQL Services "
### Changes Above Require Services to be cycled to take effect 
### Stop the SQL Service and Launchpad wild cards are used to account for named instances  
Stop-Service -Name "MSSQ*" -Force

### Start the SQL Service 
Start-Service -Name "MSSQ*"
Write-Host "SQL Services Restarted"


$Query = "CREATE LOGIN $username WITH PASSWORD=N'$password', DEFAULT_DATABASE=[master], CHECK_EXPIRATION=OFF, CHECK_POLICY=OFF"
Invoke-Sqlcmd -Query $Query -ErrorAction SilentlyContinue

$Query = "ALTER SERVER ROLE [sysadmin] ADD MEMBER $username"
Invoke-Sqlcmd -Query $Query -ErrorAction SilentlyContinue



Write-Host "Done with configuration changes to SQL Server"

Write-Host "Installing latest Power BI..."
# Download PowerBI Desktop installer
Start-BitsTransfer -Source "https://go.microsoft.com/fwlink/?LinkId=521662&clcid=0x409" -Destination powerbi-desktop.msi

# Silently install PowerBI Desktop
msiexec.exe /i powerbi-desktop.msi /qn /norestart  ACCEPT_EULA=1

if (!$?) {
    Write-Host -ForeGroundColor Red " Error installing Power BI Desktop. Please install latest Power BI manually."
}


##Create Shortcuts and Autostart Help File 
Copy-Item "$ScriptPath\SolutionHelp.url" C:\Users\Public\Desktop\
Copy-Item "$ScriptPath\SolutionHelp.url" "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp\"
Write-Host "Help Files Copied to Desktop"




$WsShell = New-Object -ComObject WScript.Shell
$shortcut = $WsShell.CreateShortcut($desktop + $checkoutDir + ".lnk")
$shortcut.TargetPath = $solutionPath
$shortcut.Save()

$ConfigureSql = "C:\Solutions\Hospital\Resources\ActionScripts\ConfigureSQL.ps1  $ServerName $SolutionName $InstallPy $Prompt"
Invoke-Expression $ConfigureSQL 


# install modules for sample website
if(($SampleWeb  -eq "Yes") -and ($isDsvm = "Yes"))
{
set-location $SolutionPath\Website\
npm install
(Get-Content $SolutionPath\Website\server.js).replace('XXYOURSQLPW', $password) | Set-Content $SolutionPath\Website\server.js
(Get-Content $SolutionPath\Website\server.js).replace('XXYOURSQLUSER', $username) | Set-Content $SolutionPath\Website\server.js
}

$endTime = Get-Date

Write-Host ("Length of Stay Development Workflow Finished Successfully!")
$Duration = New-TimeSpan -Start $StartTime -End $EndTime 
Write-Host ("Total Deployment Time = $Duration") 

Stop-Transcript


##Launch HelpURL 
Start-Process "https://microsoft.github.io/r-server-hospital-length-of-stay/Typical.html"


    ## Close Powershell if not run on 
   ## if ($baseurl)
    Exit-PSHostProcess
    EXIT

}


ELSE 
{ 
    
    Write-Host "To install this Solution you need to run Powershell as an Administrator. This program will close automatically in 20 seconds"
    Start-Sleep -s 20


## Close Powershell 
Exit-PSHostProcess
EXIT }