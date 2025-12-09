<#
.SYNOPSIS
    OpenTuneAdapter - Control Plane Integration Module

.DESCRIPTION
    This module provides integration with the OpenTune control plane.
    It handles communication with the server, fetching desired state,
    downloading configuration packages, and reporting run results.
    
    Uses DscGitCore for actual DSC execution.

.NOTES
    Module: OpenTuneAdapter
    Version: 1.0.0
    Requires: DscGitCore module
#>

# =============================================================================
# Module Configuration
# =============================================================================

$script:ModuleVersion = "1.0.0"
$script:UserAgent = "opentune-agent/1.0.0"
$script:RetryDelaySeconds = @(5, 15, 30)

# Import DscGitCore if not already loaded
$modulePath = Join-Path $PSScriptRoot "DscGitCore.psm1"
if (Test-Path $modulePath) {
    Import-Module $modulePath -Force -DisableNameChecking
}

# =============================================================================
# API Communication
# =============================================================================

function Invoke-OpenTuneApi {
    <#
    .SYNOPSIS
        Make an authenticated API call to the OpenTune server.
    
    .PARAMETER Method
        HTTP method (GET, POST, etc.)
    
    .PARAMETER Url
        Full URL to call.
    
    .PARAMETER NodeToken
        Node authentication token.
    
    .PARAMETER Body
        Optional request body (will be converted to JSON).
    
    .PARAMETER OutFile
        Optional file path to save response (for downloads).
    
    .PARAMETER MaxAttempts
        Maximum retry attempts.
    
    .OUTPUTS
        The API response object, or $true for file downloads.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Method,
        
        [Parameter(Mandatory)]
        [string]$Url,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [hashtable]$Body = $null,
        
        [string]$OutFile = $null,
        
        [int]$MaxAttempts = 3
    )
    
    $headers = @{
        "X-Node-Token" = $NodeToken
        "Content-Type" = "application/json"
        "User-Agent"   = $script:UserAgent
    }
    
    $attempt = 0
    $lastError = $null
    
    while ($attempt -lt $MaxAttempts) {
        $attempt++
        
        try {
            $params = @{
                Method      = $Method
                Uri         = $Url
                Headers     = $headers
                ErrorAction = "Stop"
            }
            
            if ($Body) {
                $params.Body = ($Body | ConvertTo-Json -Depth 10)
            }
            
            if ($OutFile) {
                $params.OutFile = $OutFile
                Invoke-WebRequest @params
                return $true
            }
            else {
                return Invoke-RestMethod @params
            }
        }
        catch {
            $lastError = $_
            $statusCode = $_.Exception.Response.StatusCode.value__
            
            # Don't retry on client errors (4xx) except 429
            if ($statusCode -ge 400 -and $statusCode -lt 500 -and $statusCode -ne 429) {
                Write-DscLog "API error (non-retryable): $statusCode - $($_.Exception.Message)" -Level ERROR
                throw
            }
            
            if ($attempt -lt $MaxAttempts) {
                $delay = $script:RetryDelaySeconds[$attempt - 1]
                Write-DscLog "API request failed (attempt $attempt/$MaxAttempts). Retrying in ${delay}s..." -Level WARN
                Start-Sleep -Seconds $delay
            }
        }
    }
    
    Write-DscLog "API request failed after $MaxAttempts attempts" -Level ERROR
    throw $lastError
}

# =============================================================================
# OpenTune API Functions
# =============================================================================

function Get-OpenTuneDesiredState {
    <#
    .SYNOPSIS
        Fetch the desired state for a node from the OpenTune server.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ServerUrl,
        
        [Parameter(Mandatory)]
        [int]$NodeId,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [int]$MaxRetries = 3
    )
    
    $url = "$ServerUrl/api/v1/agents/nodes/$NodeId/desired-state"
    Write-DscLog "Fetching desired state from: $url"
    
    return Invoke-OpenTuneApi -Method GET -Url $url -NodeToken $NodeToken -MaxAttempts $MaxRetries
}

function Get-OpenTunePackage {
    <#
    .SYNOPSIS
        Download the configuration package from the OpenTune server.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$PackageUrl,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [Parameter(Mandatory)]
        [string]$OutputPath,
        
        [int]$MaxRetries = 3
    )
    
    Write-DscLog "Downloading package from: $PackageUrl"
    
    return Invoke-OpenTuneApi -Method GET -Url $PackageUrl -NodeToken $NodeToken -OutFile $OutputPath -MaxAttempts $MaxRetries
}

function Send-OpenTuneRunReport {
    <#
    .SYNOPSIS
        Send a run report to the OpenTune server.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ServerUrl,
        
        [Parameter(Mandatory)]
        [int]$NodeId,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [Parameter(Mandatory)]
        [hashtable]$ReportData,
        
        [int]$MaxRetries = 3
    )
    
    $url = "$ServerUrl/api/v1/agents/nodes/$NodeId/runs"
    Write-DscLog "Reporting run to: $url (status: $($ReportData.status))"
    
    return Invoke-OpenTuneApi -Method POST -Url $url -NodeToken $NodeToken -Body $ReportData -MaxAttempts $MaxRetries
}

function Send-OpenTuneHeartbeat {
    <#
    .SYNOPSIS
        Send a heartbeat to the OpenTune server.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$ServerUrl,
        
        [Parameter(Mandatory)]
        [int]$NodeId,
        
        [Parameter(Mandatory)]
        [string]$NodeToken
    )
    
    $url = "$ServerUrl/api/v1/agents/nodes/$NodeId/heartbeat"
    Write-DscLog "Sending heartbeat to: $url" -Level DEBUG
    
    return Invoke-OpenTuneApi -Method POST -Url $url -NodeToken $NodeToken -MaxAttempts 1
}

# =============================================================================
# Main Exported Function
# =============================================================================

function Invoke-OpenTuneOnce {
    <#
    .SYNOPSIS
        Execute a single reconciliation cycle with the OpenTune control plane.
    
    .DESCRIPTION
        This function:
        1. Fetches the desired state from the server
        2. Downloads the configuration package (if using Gitless mode)
        3. Executes the DSC configuration using DscGitCore
        4. Reports the result back to the server
    
    .PARAMETER ServerUrl
        The OpenTune server URL (e.g., http://opentune.local:8000)
    
    .PARAMETER NodeId
        The node ID assigned by the server.
    
    .PARAMETER NodeToken
        The node authentication token.
    
    .PARAMETER WorkDir
        Working directory for downloads and extraction.
    
    .PARAMETER UseGit
        If $true, use Git to clone the repo directly (requires Git).
        If $false, download ZIP package from server (Gitless mode).
        Default: $false (Gitless)
    
    .PARAMETER Force
        Force apply even if system is already in desired state.
    
    .PARAMETER MaxRetries
        Maximum API retry attempts.
    
    .OUTPUTS
        Hashtable with status, summary, and commit properties.
    
    .EXAMPLE
        $result = Invoke-OpenTuneOnce -ServerUrl "http://server:8000" -NodeId 1 -NodeToken "xxx"
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ServerUrl,
        
        [Parameter(Mandatory)]
        [int]$NodeId,
        
        [Parameter(Mandatory)]
        [string]$NodeToken,
        
        [string]$WorkDir = "C:\dsc-agent\work",
        
        [switch]$UseGit,
        
        [switch]$Force,
        
        [int]$MaxRetries = 3
    )
    
    $result = @{
        status  = "failed"
        summary = ""
        commit  = $null
    }
    
    $serverUrl = $ServerUrl.TrimEnd("/")
    
    try {
        Write-DscLog "========================================" 
        Write-DscLog "OpenTuneAdapter - Centralized Mode"
        Write-DscLog "========================================"
        Write-DscLog "Server: $serverUrl"
        Write-DscLog "Node ID: $NodeId"
        Write-DscLog "Mode: $(if ($UseGit) { 'Git' } else { 'Package (Gitless)' })"
        
        # Ensure work directory exists
        Ensure-Directory -Path $WorkDir
        
        # Get desired state
        $desiredState = Get-OpenTuneDesiredState -ServerUrl $serverUrl `
                                                  -NodeId $NodeId `
                                                  -NodeToken $NodeToken `
                                                  -MaxRetries $MaxRetries
        
        if (-not $desiredState.policy_assigned) {
            Write-DscLog "No policy assigned to this node"
            $result.status = "skipped"
            $result.summary = "No policy assigned"
            return $result
        }
        
        $policyId = $desiredState.policy_id
        $policyName = $desiredState.policy_name
        $configPath = $desiredState.config_path
        
        Write-DscLog "Policy: $policyName (ID: $policyId)"
        Write-DscLog "Config path: $configPath"
        
        # Execute DSC based on mode
        if ($UseGit) {
            # Git mode - clone directly
            $repoUrl = $desiredState.repository.url
            $branch = $desiredState.repository.branch
            
            Write-DscLog "Using Git mode - cloning from: $repoUrl"
            
            $dscResult = Invoke-DscFromGit -RepoUrl $repoUrl `
                                           -Branch $branch `
                                           -ConfigPath $configPath `
                                           -WorkDir $WorkDir `
                                           -Force:$Force
        }
        else {
            # Package mode - download ZIP from server
            $packageUrl = $desiredState.package_url
            
            if (-not $packageUrl) {
                # Construct URL if not provided
                $packageUrl = "$serverUrl/api/v1/agents/nodes/$NodeId/package"
            }
            
            Write-DscLog "Using Package mode (Gitless)"
            
            # Download package
            $packageDir = Join-Path $WorkDir "packages"
            Ensure-Directory -Path $packageDir
            $zipPath = Join-Path $packageDir "config-$policyId.zip"
            
            Get-OpenTunePackage -PackageUrl $packageUrl `
                                -NodeToken $NodeToken `
                                -OutputPath $zipPath `
                                -MaxRetries $MaxRetries
            
            # Execute from package
            $dscResult = Invoke-DscFromPackage -PackagePath $zipPath `
                                               -ConfigPath $configPath `
                                               -WorkDir $WorkDir `
                                               -Force:$Force
        }
        
        $result.status = $dscResult.status
        $result.summary = $dscResult.summary
        $result.commit = $dscResult.commit
        
        # Report results to server
        $reportData = @{
            policy_id  = $policyId
            git_commit = $result.commit
            status     = $result.status
            summary    = $result.summary
        }
        
        try {
            $reportResponse = Send-OpenTuneRunReport -ServerUrl $serverUrl `
                                                      -NodeId $NodeId `
                                                      -NodeToken $NodeToken `
                                                      -ReportData $reportData `
                                                      -MaxRetries $MaxRetries
            
            Write-DscLog "Run reported successfully. Run ID: $($reportResponse.run_id)"
        }
        catch {
            Write-DscLog "Failed to report run: $($_.Exception.Message)" -Level WARN
            # Don't fail the whole operation just because reporting failed
        }
        
        Write-DscLog "========================================"
        Write-DscLog "Result: $($result.status)"
        Write-DscLog "========================================"
        
        return $result
    }
    catch {
        $result.status = "failed"
        $result.summary = "Error: $($_.Exception.Message)"
        Write-DscLog $result.summary -Level ERROR
        
        # Try to report the failure
        try {
            Send-OpenTuneRunReport -ServerUrl $serverUrl `
                                   -NodeId $NodeId `
                                   -NodeToken $NodeToken `
                                   -ReportData @{
                                       policy_id  = 0
                                       git_commit = $null
                                       status     = "failed"
                                       summary    = $result.summary
                                   } `
                                   -MaxRetries 1 | Out-Null
        }
        catch {
            Write-DscLog "Failed to report error to server" -Level WARN
        }
        
        return $result
    }
}

# =============================================================================
# Module Exports
# =============================================================================

Export-ModuleMember -Function @(
    'Invoke-OpenTuneOnce',
    'Get-OpenTuneDesiredState',
    'Get-OpenTunePackage',
    'Send-OpenTuneRunReport',
    'Send-OpenTuneHeartbeat',
    'Invoke-OpenTuneApi'
)
