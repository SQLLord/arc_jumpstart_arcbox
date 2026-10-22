$ErrorActionPreference = $env:ErrorActionPreference

$Env:ArcBoxDir = 'C:\ArcBox'
$Env:ArcBoxLogsDir = "$Env:ArcBoxDir\Logs"
$tenantId = $env:tenantId
$subscriptionId = $env:subscriptionId
$resourceGroup = $env:resourceGroup

$logFilePath = Join-Path -Path $Env:ArcBoxLogsDir -ChildPath ('WinGet-provisioning-' + (Get-Date -Format 'yyyyMMddHHmmss') + '.log')

Start-Transcript -Path $logFilePath -Force -ErrorAction SilentlyContinue

function Set-DeploymentProgress {
    param([string]$Status)
    $tags = Get-AzResourceGroup -Name $resourceGroup | Select-Object -ExpandProperty Tags
    if ($null -ne $tags) {
        $tags["DeploymentProgress"] = $Status
    } else {
        $tags = @{"DeploymentProgress" = $Status}
    }
    $null = Set-AzResourceGroup -ResourceGroupName $resourceGroup -Tag $tags
    $null = Set-AzResource -ResourceName $env:computername -ResourceGroupName $resourceGroup -ResourceType "microsoft.compute/virtualmachines" -Tag $tags -Force
}

# PowerShell Gallery downloads occasionally fail with transient errors (for example 404 on a package that exists), so retry
function Install-PSResourceWithRetry {
    param(
        [string]$Name,
        [switch]$Prerelease,
        [int]$MaxAttempts = 3
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            Install-PSResource -Name $Name -Scope AllUsers -Quiet -AcceptLicense -TrustRepository -Prerelease:$Prerelease -ErrorAction Stop
            return
        }
        catch {
            Write-Warning "Installing PowerShell module $Name failed (attempt $attempt of $MaxAttempts): $($_.Exception.Message)"
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (30 * $attempt) }
        }
    }
    Write-Warning "Could not install PowerShell module $Name; winget configure will try to download it if a configuration needs it"
}

# Re-applying a configuration is safe (units already in the desired state are skipped), so retry until it fully applies
function Invoke-WinGetConfiguration {
    param(
        [string]$File,
        [int]$MaxAttempts = 3
    )
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        winget configure --file $File --accept-configuration-agreements --disable-interactivity
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Warning "WinGet configuration $File did not fully apply (exit code $LASTEXITCODE, attempt $attempt of $MaxAttempts)"
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (60 * $attempt) }
    }
    return $false
}

Connect-AzAccount -Identity -Tenant $tenantId -Subscription $subscriptionId

Set-DeploymentProgress -Status "Installing WinGet packages..."

# Install WinGet PowerShell modules
Install-PSResourceWithRetry -Name Microsoft.WinGet.Client
Install-PSResourceWithRetry -Name Microsoft.WinGet.DSC

# Install DSC resources required for ArcBox
Install-PSResourceWithRetry -Name DSCR_Font
Install-PSResourceWithRetry -Name HyperVDsc -Prerelease
Install-PSResourceWithRetry -Name NetworkingDsc

# Update WinGet package manager to the latest version (running twice due to a known issue regarding WinAppSDK)
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose
Repair-WinGetPackageManager -AllUsers -Force -Latest -Verbose

# Apply WinGet Configuration files
$failedConfigurations = @()
$configurations = @('C:\ArcBox\DSC\common.dsc.yml')
switch ($env:flavor) {
    'DevOps' { $configurations += 'C:\ArcBox\DSC\devops.dsc.yml' }
    'DataOps' { $configurations += 'C:\ArcBox\DSC\dataops.dsc.yml' }
    'ITPro' { $configurations += 'C:\ArcBox\DSC\itpro.dsc.yml' }
}
foreach ($configuration in $configurations) {
    if (-not (Invoke-WinGetConfiguration -File $configuration)) {
        $failedConfigurations += Split-Path -Path $configuration -Leaf
    }
}

# BGInfo is downloaded directly: the winget package often fails with a hash mismatch (0x8A150011) because Sysinternals updates the download in place
if (-not (Get-Command bginfo.exe -ErrorAction SilentlyContinue)) {
    Write-Host "Downloading BGInfo from Sysinternals"
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
        Write-Warning "BGInfo download failed: $_"
    }
}

# The logon scripts cannot run without these tools, so check for them before starting the scripts
$env:Path = [Environment]::GetEnvironmentVariable('Path', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('Path', 'User')
$requiredTools = @('az', 'azcopy')
if ($env:flavor -in 'DevOps', 'DataOps') { $requiredTools += 'kubectl', 'helm' }
$missingTools = @($requiredTools | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) })

if ($missingTools.Count -gt 0) {
    $failureMessage = "Failed to install $($missingTools -join ', ')$(if ($failedConfigurations) { " ($($failedConfigurations -join ', ') did not apply)" }). Sign out and back in to the client VM to retry, see C:\ArcBox\Logs\WinGet-provisioning-*.log"
    Write-Error $failureMessage -ErrorAction Continue
    Set-DeploymentProgress -Status $failureMessage

    # Leave the WinGetLogonScript task registered so the next logon runs this script again, and do not start the logon scripts
    Stop-Transcript
    exit 1
}

if ($failedConfigurations) {
    Write-Warning "These WinGet configurations did not fully apply, but the required tools are installed: $($failedConfigurations -join ', ')"
}

# Start remaining logon scripts
Get-ScheduledTask *LogonScript* | Where-Object TaskName -ne 'WinGetLogonScript' | Start-ScheduledTask

#Cleanup
Unregister-ScheduledTask -TaskName 'WinGetLogonScript' -Confirm:$false
Stop-Transcript
