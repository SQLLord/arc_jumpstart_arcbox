##############################################################
# This script will install ADDS window feature and promote windows server
# as a domain controller and restarts to finish AD setup
##############################################################
# Configure the Domain Controller
param (
    [string]$domainName,
    [string]$domainAdminUsername,
    [string]$templateBaseUrl,
    [string]$keyVaultName
)

[System.Environment]::SetEnvironmentVariable('domainName', $domainName,[System.EnvironmentVariableTarget]::Machine)
[System.Environment]::SetEnvironmentVariable('domainAdminUsername', $domainAdminUsername,[System.EnvironmentVariableTarget]::Machine)

$Env:ArcBoxLogsDir = "C:\ArcBox\Logs"

Start-Transcript -Path "$Env:ArcBoxLogsDir\SetupADDS.log"

# PowerShell Gallery downloads fail transiently (for example "No match was found" or 404 for a module that exists), so retry with backoff
function Invoke-WithRetry {
    param([string]$Description, [scriptblock]$ScriptBlock, [int]$MaxAttempts = 3)
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            & $ScriptBlock
            return $true
        }
        catch {
            Write-Warning "$Description failed (attempt $attempt of $MaxAttempts): $($_.Exception.Message)"
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (30 * $attempt) }
        }
    }
    return $false
}

$null = Invoke-WithRetry -Description 'Installing the NuGet package provider' -ScriptBlock { Install-PackageProvider -Name NuGet -MinimumVersion 2.8.5.201 -Force -ErrorAction Stop }

$null = Invoke-WithRetry -Description 'Installing PowerShell module Microsoft.PowerShell.PSResourceGet' -ScriptBlock { Install-Module -Name Microsoft.PowerShell.PSResourceGet -Force -ErrorAction Stop }
if (-not (Get-Module -ListAvailable -Name Microsoft.PowerShell.PSResourceGet)) {
    # Fall back to downloading the package directly, which skips the Gallery search that fails
    $null = Invoke-WithRetry -Description 'Downloading Microsoft.PowerShell.PSResourceGet directly' -ScriptBlock {
        $nupkgPath = Join-Path $env:TEMP 'Microsoft.PowerShell.PSResourceGet.zip'
        $extractPath = Join-Path $env:TEMP 'Microsoft.PowerShell.PSResourceGet'
        Invoke-WebRequest -Uri 'https://www.powershellgallery.com/api/v2/package/Microsoft.PowerShell.PSResourceGet' -OutFile $nupkgPath -UseBasicParsing -ErrorAction Stop
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction SilentlyContinue
        Expand-Archive -Path $nupkgPath -DestinationPath $extractPath -Force
        $moduleVersion = ([xml](Get-Content -Path (Join-Path $extractPath 'Microsoft.PowerShell.PSResourceGet.nuspec') -Raw)).package.metadata.version
        Remove-Item -Path (Join-Path $extractPath '_rels'), (Join-Path $extractPath 'package'), (Join-Path $extractPath '*.nuspec'), (Join-Path $extractPath '`[Content_Types`].xml') -Recurse -Force -ErrorAction SilentlyContinue
        $moduleDir = Join-Path $env:ProgramFiles "WindowsPowerShell\Modules\Microsoft.PowerShell.PSResourceGet\$moduleVersion"
        New-Item -Path $moduleDir -ItemType Directory -Force | Out-Null
        Copy-Item -Path (Join-Path $extractPath '*') -Destination $moduleDir -Recurse -Force
    }
}
Import-Module Microsoft.PowerShell.PSResourceGet -ErrorAction SilentlyContinue
if (-not (Get-Command Install-PSResource -ErrorAction SilentlyContinue)) {
    throw "Microsoft.PowerShell.PSResourceGet could not be installed from the PowerShell Gallery. Check C:\ArcBox\Logs\SetupADDS.log and redeploy."
}

$modules = @("Az.KeyVault", "Azure.Arc.Jumpstart.Common", "Microsoft.PowerShell.SecretManagement", "Pester")

foreach ($module in $modules) {
    $installed = Invoke-WithRetry -Description "Installing PowerShell module $module" -ScriptBlock { Install-PSResource -Name $module -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -ErrorAction Stop }
    # The domain controller setup reads the Key Vault, so it cannot continue without these
    if (-not $installed -and $module -in 'Az.KeyVault', 'Microsoft.PowerShell.SecretManagement') {
        throw "Could not install PowerShell module $module from the PowerShell Gallery. Check C:\ArcBox\Logs\SetupADDS.log and redeploy."
    }
}

# Connect to Azure using Managed Identity
Connect-AzAccount -Identity

# Get the resource group name from the Azure Instance Metadata Service
$metadataUrl = "http://169.254.169.254/metadata/instance/compute?api-version=2021-02-01"
$headers = @{ "Metadata" = "true" }
$response = Invoke-RestMethod -Uri $metadataUrl -Method Get -Headers $headers
$resourceGroup = $response.resourceGroupName

# Use the Key Vault name passed in by the deployment; fall back to the single vault in the resource group
if ($keyVaultName) {
    $KeyVault = Get-AzKeyVault -VaultName $keyVaultName -ResourceGroupName $resourceGroup
}
else {
    $KeyVault = @(Get-AzKeyVault -ResourceGroupName $resourceGroup)
    if ($KeyVault.Count -ne 1) {
        throw "Expected exactly one Key Vault in resource group '$resourceGroup' but found $($KeyVault.Count). Pass -keyVaultName explicitly."
    }
    $KeyVault = $KeyVault[0]
}
if (-not $KeyVault) {
    throw "Key Vault '$keyVaultName' was not found in resource group '$resourceGroup'."
}

# Set Key Vault Name as an environment variable
[System.Environment]::SetEnvironmentVariable('keyVaultName', $KeyVault.VaultName, [System.EnvironmentVariableTarget]::Machine)

# Import required module
Import-Module Microsoft.PowerShell.SecretManagement

# Register the Azure Key Vault as a secret vault if not already registered
# Ensure you have installed the SecretManagement and SecretStore modules along with the Key Vault extension

if (-not (Get-SecretVault -Name $KeyVault.VaultName -ErrorAction Ignore)) {
    Register-SecretVault -Name $KeyVault.VaultName -ModuleName Az.KeyVault -VaultParameters @{ AZKVaultName = $KeyVault.VaultName } -DefaultVault
}

# Fetch windowsAdminPassword from Key Vault (assumes $env:KeyVaultName is defined)
$windowsAdminPasswordSecret = Get-Secret -Name windowsAdminPassword -AsPlainText
$secureDomainAdminPassword = $windowsAdminPasswordSecret | ConvertTo-SecureString -AsPlainText -Force

# Set Diagnostic Data settings

$telemetryPath = "HKLM:\Software\Policies\Microsoft\Windows\DataCollection"
$telemetryProperty = "AllowTelemetry"
$telemetryValue = 3

$oobePath = "HKLM:\Software\Policies\Microsoft\Windows\OOBE"
$oobeProperty = "DisablePrivacyExperience"
$oobeValue = 1

# Create the registry key and set the value for AllowTelemetry
if (-not (Test-Path $telemetryPath)) {
    New-Item -Path $telemetryPath -Force | Out-Null
}
Set-ItemProperty -Path $telemetryPath -Name $telemetryProperty -Value $telemetryValue

# Create the registry key and set the value for DisablePrivacyExperience
if (-not (Test-Path $oobePath)) {
    New-Item -Path $oobePath -Force | Out-Null
}
Set-ItemProperty -Path $oobePath -Name $oobeProperty -Value $oobeValue

Write-Host "Registry keys and values for Diagnostic Data settings have been set successfully."

# Enable ADDS windows feature to setup domain forest
Install-WindowsFeature -Name AD-Domain-Services -IncludeManagementTools

Write-Host "Finished enabling ADDS windows feature."

$netbiosname = $domainName.Split('.')[0].ToUpper()

# Create Active Directory Forest
Install-ADDSForest `
    -DomainName "$domainName" `
    -CreateDnsDelegation:$false `
    -DatabasePath "C:\Windows\NTDS" `
    -DomainMode "7" `
    -DomainNetbiosName $netbiosname `
    -ForestMode "7" `
    -InstallDns:$true `
    -LogPath "C:\Windows\NTDS" `
    -NoRebootOnCompletion:$True `
    -SysvolPath "C:\Windows\SYSVOL" `
    -Force:$true `
    -SafeModeAdministratorPassword $secureDomainAdminPassword

Write-Host "ADDS Deployment successful. Now rebooting computer to finsih setup."

# schedule task to run after reboot to create reverse DNS lookup
# $Trigger = New-ScheduledTaskTrigger -AtStartup
# $Action = New-ScheduledTaskAction -Execute "PowerShell.exe" -Argument 'C:\Temp\RunAfterADDSRestart.ps1'
# Register-ScheduledTask -TaskName "RunAfterADDSRestart" -Trigger $Trigger -User SYSTEM -Action $Action -RunLevel "Highest" -Force

# Reboot computer
Restart-Computer
Write-Host "System reboot requested."

Stop-Transcript
