$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$resourceGroup = $env:resourceGroup

$logFilePath = Join-Path -Path $Env:ArcBoxLogsDir -ChildPath ('WinGet-provisioning-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

$DeploymentProgressString = "Installing WinGet packages..."

Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId

$tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags

if ($null -ne $tags) {
    $tags["DeploymentProgress"] = $DeploymentProgressString
} else {
    $tags = @{"DeploymentProgress" = $DeploymentProgressString}
}

$null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags
$null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $resourceGroup -ResourceType "microsoft.compute/virtualmachines" -Tag $tags -Force

# Install WinGet PowerShell modules
Install-PSResource -Name Microsoft.WinGet.Client -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
Install-PSResource -Name Microsoft.WinGet.DSC -Scope AllUsers -Quiet -AcceptLicense -TrustRepository

# Install DSC resources required for ArcBox
Install-PSResource -Name DSCR_Font -Scope AllUsers -Quiet -AcceptLicense -TrustRepository
Install-PSResource -Name HyperVDsc -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Prerelease
Install-PSResource -Name NetworkingDsc -Scope AllUsers -Quiet -AcceptLicense -TrustRepository

# Update WinGet package manager to the latest version (running twice due to a known issue regarding WinAppSDK)
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose

# Apply WinGet Configuration files
winget configure --file C:\ArcBox\DSC\common.dsc.yml --accept-configuration-agreements --disable-interactivity

switch ($env:flavor) {
    'DevOps' { winget configure --file C:\ArcBox\DSC\devops.dsc.yml --accept-configuration-agreements --disable-interactivity }
    'DataOps' { winget configure --file C:\ArcBox\DSC\dataops.dsc.yml --accept-configuration-agreements --disable-interactivity }
    'ITPro' { winget configure --file C:\ArcBox\DSC\itpro.dsc.yml --accept-configuration-agreements --disable-interactivity }
}

# Fallback for BGInfo: the winget package often fails with a hash mismatch (0x8A150011) because Sysinternals updates the download in place
if (-not (Get-Command bginfo.exe -ErrorAction SilentlyContinue)) {
    Write-Host "BGInfo not found after WinGet configuration, downloading it from Sysinternals"
    $bgInfoDir = 'C:\Tools\BGInfo'
    $bgInfoZip = Join-Path $env:TEMP 'BGInfo.zip'
    try {
        Invoke-WebRequest -Uri 'https://download.sysinternals.com/files/BGInfo.zip' -OutFile $bgInfoZip -UseBasicParsing
        Expand-Archive -Path $bgInfoZip -DestinationPath $bgInfoDir -Force
        Copy-Item -Path (Join-Path $bgInfoDir 'Bginfo64.exe') -Destination (Join-Path $bgInfoDir 'bginfo.exe') -Force

        $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
        if ($machinePath -notlike "*$bgInfoDir*") {
            [Environment]::SetEnvironmentVariable('Path', "$machinePath;$bgInfoDir", 'Machine')
        }
        $env:Path += ";$bgInfoDir"
        Write-Host "BGInfo installed to $bgInfoDir"
    }
    catch {
        Write-Warning "BGInfo fallback download failed: $_"
    }
}

# Start remaining logon scripts
Get-ScheduledTask *LogonScript* | Start-ScheduledTask

#Cleanup
Unregister-ScheduledTask -TaskName 'WinGetLogonScript' -Confirm:$false
Stop-Transcript