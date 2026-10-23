function Write-Header {
    param (
        [string]
        $title
    )

    Write-Host
    Write-Host ("#" * ($title.Length + 8))
    Write-Host "# - $title"
    Write-Host ("#" * ($title.Length + 8))
    Write-Host
}

function exec
{
    param
    (
        [ScriptBlock] $ScriptBlock,
        [string] $StderrPrefix = "",
        [int[]] $AllowedExitCodes = @(0)
    )
 
    $backupErrorActionPreference = $script:ErrorActionPreference
 
    $script:ErrorActionPreference = "Continue"
    try
    {
        & $ScriptBlock 2>&1 | ForEach-Object -Process `
            {
                if ($_ -is [System.Management.Automation.ErrorRecord])
                {
                    "$StderrPrefix$_"
                }
                else
                {
                    "$_"
                }
            }
        if ($AllowedExitCodes -notcontains $LASTEXITCODE)
        {
            throw "Execution failed with exit code $LASTEXITCODE"
        }
    }
    finally
    {
        $script:ErrorActionPreference = $backupErrorActionPreference
    }
}

# Downloads fail transiently (GitHub, PowerShell Gallery and CDN hiccups), so retry with backoff.
# Throws after the last attempt, or only warns with -Optional for downloads ArcBox can do without.
function Invoke-WebRequestWithRetry {
    param (
        [Parameter(Mandatory, Position = 0)]
        [string] $Uri,
        [string] $OutFile,
        [int] $MaxAttempts = 3,
        [switch] $Optional
    )

    # The progress bar slows Invoke-WebRequest down a lot in Windows PowerShell
    $ProgressPreference = 'SilentlyContinue'
    $requestParams = @{ Uri = $Uri; UseBasicParsing = $true; ErrorAction = 'Stop' }
    if ($OutFile) { $requestParams.OutFile = $OutFile }
    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        try {
            return Invoke-WebRequest @requestParams
        }
        catch {
            $errorMessage = $_.Exception.Message
            Write-Warning "Downloading $Uri failed (attempt $attempt of $MaxAttempts): $errorMessage"
            if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds (15 * $attempt) }
        }
    }
    if ($Optional) {
        Write-Warning "Skipping $Uri after $MaxAttempts failed attempts"
        return
    }
    throw "Downloading $Uri failed after $MaxAttempts attempts: $errorMessage"
}

# Retries a native command (az, azcopy, winget) until it exits with 0. Returns $true on success and $false after the last attempt.
function Invoke-NativeCommandWithRetry {
    param (
        [Parameter(Mandatory, Position = 0)]
        [ScriptBlock] $ScriptBlock,
        [Parameter(Mandatory)]
        [string] $Description,
        [int] $MaxAttempts = 3,
        [int] $DelaySeconds = 30
    )

    for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
        # Out-Host keeps the command's output in the transcript instead of returning it as part of this function's result
        & $ScriptBlock | Out-Host
        if ($LASTEXITCODE -eq 0) { return $true }
        Write-Warning "$Description failed (exit code $LASTEXITCODE, attempt $attempt of $MaxAttempts)"
        if ($attempt -lt $MaxAttempts) { Start-Sleep -Seconds ($DelaySeconds * $attempt) }
    }
    return $false
}
