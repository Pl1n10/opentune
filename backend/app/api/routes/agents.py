"""
Agent communication routes.

These endpoints are used by the dsc-cp agent running on Windows nodes.
Authentication is via X-Node-Token header.

New endpoints for Gitless operation:
- GET /agents/nodes/{node_id}/package - Download config ZIP package
- GET /agents/nodes/{node_id}/bootstrap.ps1 - Download bootstrap script (admin-only)
"""

import os
from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, Header, Request, Response
from fastapi.responses import PlainTextResponse, StreamingResponse
from sqlmodel import Session
from pydantic import BaseModel
import io

from app.core.db import get_session
from app.core.security import verify_token, verify_admin_api_key, generate_node_token, hash_token
from app.core.exceptions import not_found, unauthorized, bad_request
from app.core.config import get_settings
from app.core import repo_service
from app.models import Node, Policy, GitRepository, ReconciliationRun
from app.schemas import RunReport, NodeRead

settings = get_settings()
router = APIRouter(prefix="/agents", tags=["agents"])


# ============================================================================
# Response Models
# ============================================================================

class DesiredStateResponse(BaseModel):
    """Response for the desired-state endpoint."""
    policy_assigned: bool
    policy_id: Optional[int] = None
    policy_name: Optional[str] = None
    repository: Optional[dict] = None
    config_path: Optional[str] = None
    # New field for gitless mode
    package_url: Optional[str] = None


class RunReportResponse(BaseModel):
    """Response after reporting a run."""
    ok: bool
    run_id: int
    message: str = "Run recorded successfully"


class HeartbeatResponse(BaseModel):
    """Response for heartbeat endpoint."""
    ok: bool
    server_time: datetime
    node_id: int
    node_name: str


class BootstrapResponse(BaseModel):
    """Response after generating bootstrap script."""
    node: NodeRead
    token: str
    bootstrap_url: str


# ============================================================================
# Helper Functions
# ============================================================================

def authenticate_node(
    node_id: int,
    token: str,
    session: Session,
) -> Node:
    """
    Authenticate a node by ID and token.
    Returns the Node if valid, raises HTTPException otherwise.
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    if not verify_token(token, node.node_token_hash):
        raise unauthorized("Invalid node token")
    
    return node


def get_server_url(request: Request) -> str:
    """Get the server URL for bootstrap scripts."""
    if settings.SERVER_URL:
        return settings.SERVER_URL.rstrip("/")
    
    # Auto-detect from request
    scheme = request.headers.get("x-forwarded-proto", request.url.scheme)
    host = request.headers.get("x-forwarded-host", request.headers.get("host", "localhost:8000"))
    return f"{scheme}://{host}"


# ============================================================================
# Agent Endpoints
# ============================================================================

@router.get("/nodes/{node_id}/desired-state", response_model=DesiredStateResponse)
def get_desired_state(
    node_id: int,
    request: Request,
    x_node_token: str = Header(..., alias="X-Node-Token"),
    session: Session = Depends(get_session),
):
    """
    Get the desired state for a node.
    
    Called by the agent to determine what configuration to apply.
    Returns policy info and package URL for gitless operation.
    """
    node = authenticate_node(node_id, x_node_token, session)
    
    # Update last_seen
    node.last_seen_at = datetime.utcnow()
    session.add(node)
    session.commit()
    
    if not node.assigned_policy_id:
        return DesiredStateResponse(policy_assigned=False)
    
    policy = session.get(Policy, node.assigned_policy_id)
    if not policy:
        return DesiredStateResponse(policy_assigned=False)
    
    repo = session.get(GitRepository, policy.git_repository_id)
    if not repo:
        return DesiredStateResponse(policy_assigned=False)
    
    server_url = get_server_url(request)
    package_url = f"{server_url}/api/v1/agents/nodes/{node_id}/package"
    
    return DesiredStateResponse(
        policy_assigned=True,
        policy_id=policy.id,
        policy_name=policy.name,
        repository={
            "id": repo.id,
            "name": repo.name,
            "branch": policy.branch or repo.default_branch,
        },
        config_path=policy.config_path,
        package_url=package_url,
    )


@router.get("/nodes/{node_id}/package")
def get_package(
    node_id: int,
    x_node_token: str = Header(..., alias="X-Node-Token"),
    session: Session = Depends(get_session),
):
    """
    Download the configuration package (ZIP) for a node.
    
    This endpoint:
    1. Resolves node → policy → repository
    2. Clones/updates the repository on the server
    3. Creates a ZIP package with the necessary files
    4. Returns the ZIP for the agent to download
    
    The agent extracts this ZIP and executes the DSC configuration.
    """
    node = authenticate_node(node_id, x_node_token, session)
    
    # Update last_seen
    node.last_seen_at = datetime.utcnow()
    session.add(node)
    
    if not node.assigned_policy_id:
        raise bad_request("No policy assigned to this node")
    
    policy = session.get(Policy, node.assigned_policy_id)
    if not policy:
        raise bad_request("Assigned policy not found")
    
    repo = session.get(GitRepository, policy.git_repository_id)
    if not repo:
        raise bad_request("Repository not found for policy")
    
    branch = policy.branch or repo.default_branch
    
    try:
        # Sync repository
        commit_hash, _ = repo_service.clone_or_update_repo(
            repo_id=repo.id,
            repo_url=repo.url,
            branch=branch,
        )
        
        # Create package
        zip_bytes, commit, package_hash = repo_service.create_package_zip(
            repo_id=repo.id,
            config_path=policy.config_path,
            branch=branch,
            include_full_repo=True,  # Include full repo for now
        )
        
        session.commit()
        
        # Return ZIP file
        filename = f"config-{node.name}-{commit[:8]}.zip"
        
        return StreamingResponse(
            io.BytesIO(zip_bytes),
            media_type="application/zip",
            headers={
                "Content-Disposition": f'attachment; filename="{filename}"',
                "X-Commit-Hash": commit,
                "X-Package-Hash": package_hash,
            }
        )
        
    except repo_service.RepoServiceError as e:
        raise bad_request(f"Failed to prepare package: {str(e)}")


@router.post("/nodes/{node_id}/runs", response_model=RunReportResponse)
def report_run(
    node_id: int,
    run: RunReport,
    x_node_token: str = Header(..., alias="X-Node-Token"),
    session: Session = Depends(get_session),
):
    """
    Report the result of a reconciliation run.
    
    Called by the agent after executing DSC configuration.
    The status should be one of: success, failed, error, skipped.
    """
    node = authenticate_node(node_id, x_node_token, session)
    
    # Verify the policy exists (or existed)
    policy = session.get(Policy, run.policy_id)
    if not policy:
        raise bad_request(f"Policy with id {run.policy_id} not found")
    
    now = datetime.utcnow()
    started_at = run.started_at or now
    
    # Create the run record
    rec_run = ReconciliationRun(
        node_id=node.id,
        policy_id=run.policy_id,
        git_commit=run.git_commit,
        status=run.status.value if hasattr(run.status, 'value') else run.status,
        summary=run.summary,
        started_at=started_at,
        finished_at=now,
    )
    
    # Update node status
    node.last_seen_at = now
    node.last_status = run.status.value if hasattr(run.status, 'value') else run.status
    
    session.add(rec_run)
    session.add(node)
    session.commit()
    session.refresh(rec_run)
    
    return RunReportResponse(
        ok=True,
        run_id=rec_run.id,
        message=f"Run recorded with status: {rec_run.status}",
    )


@router.post("/nodes/{node_id}/heartbeat", response_model=HeartbeatResponse)
def heartbeat(
    node_id: int,
    x_node_token: str = Header(..., alias="X-Node-Token"),
    session: Session = Depends(get_session),
):
    """
    Simple heartbeat endpoint to update last_seen without reporting a run.
    
    Useful for agents that want to check in even when no policy is assigned.
    """
    node = authenticate_node(node_id, x_node_token, session)
    
    node.last_seen_at = datetime.utcnow()
    session.add(node)
    session.commit()
    
    return HeartbeatResponse(
        ok=True,
        server_time=datetime.utcnow(),
        node_id=node.id,
        node_name=node.name,
    )


# ============================================================================
# Bootstrap Script Template
# ============================================================================

BOOTSTRAP_SCRIPT_TEMPLATE = r'''<#
.SYNOPSIS
    OpenTune Agent Bootstrap Script
    
.DESCRIPTION
    This script bootstraps the OpenTune DSC agent on a Windows node.
    It:
    1. Creates the agent directory structure
    2. Downloads the agent script and modules from the server
    3. Writes the configuration file (centralized mode)
    4. Creates a scheduled task for periodic reconciliation
    5. Runs the agent once immediately
    
.NOTES
    Generated for: {node_name}
    Node ID: {node_id}
    Server: {server_url}
    
    Run this script as Administrator.
#>

#Requires -RunAsAdministrator

$ErrorActionPreference = "Stop"

# =============================================================================
# Configuration (embedded by server)
# =============================================================================

$Config = @{{
    ServerUrl   = "{server_url}"
    NodeId      = {node_id}
    NodeToken   = "{node_token}"
    AgentDir    = "C:\dsc-agent"
    TaskName    = "OpenTune DSC Agent"
    IntervalMin = 30
}}

# =============================================================================
# Functions
# =============================================================================

function Write-Status {{
    param([string]$Message, [string]$Type = "INFO")
    $color = switch ($Type) {{
        "SUCCESS" {{ "Green" }}
        "WARN"    {{ "Yellow" }}
        "ERROR"   {{ "Red" }}
        default   {{ "Cyan" }}
    }}
    Write-Host "[$Type] $Message" -ForegroundColor $color
}}

function Test-AdminPrivileges {{
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}}

function Download-File {{
    param([string]$Url, [string]$OutPath)
    try {{
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri $Url -OutFile $OutPath -UseBasicParsing -ErrorAction Stop
        return $true
    }}
    catch {{
        Write-Status "Failed to download $Url : $($_.Exception.Message)" -Type ERROR
        return $false
    }}
}}

# =============================================================================
# Main Bootstrap Process
# =============================================================================

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenTune Agent Bootstrap v1.0" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Check admin
if (-not (Test-AdminPrivileges)) {{
    Write-Status "This script must be run as Administrator" -Type ERROR
    exit 1
}}

Write-Status "Node: {node_name} (ID: $($Config.NodeId))"
Write-Status "Server: $($Config.ServerUrl)"
Write-Status "Mode: Centralized (Gitless)"
Write-Host ""

# Step 1: Create directories
Write-Status "Creating agent directories..."
$dirs = @(
    $Config.AgentDir,
    (Join-Path $Config.AgentDir "modules"),
    (Join-Path $Config.AgentDir "logs"),
    (Join-Path $Config.AgentDir "work")
)
foreach ($dir in $dirs) {{
    if (-not (Test-Path $dir)) {{
        New-Item -Path $dir -ItemType Directory -Force | Out-Null
    }}
}}
Write-Status "Directories created" -Type SUCCESS

# Step 2: Write configuration (new format for dual-mode agent)
Write-Status "Writing configuration..."
$configPath = Join-Path $Config.AgentDir "config.json"
$configContent = @{{
    mode        = "centralized"
    server_url  = $Config.ServerUrl
    node_id     = $Config.NodeId
    node_token  = $Config.NodeToken
    use_git     = $false
}} | ConvertTo-Json

Set-Content -Path $configPath -Value $configContent -Force

# Secure the config file (only Administrators and SYSTEM)
$acl = Get-Acl $configPath
$acl.SetAccessRuleProtection($true, $false)
$adminRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "Administrators", "FullControl", "Allow")
$systemRule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "SYSTEM", "FullControl", "Allow")
$acl.SetAccessRule($adminRule)
$acl.SetAccessRule($systemRule)
Set-Acl -Path $configPath -AclObject $acl

Write-Status "Configuration written and secured" -Type SUCCESS

# Step 3: Download agent script and modules
Write-Status "Downloading agent components..."

$baseUrl = $Config.ServerUrl
$downloads = @(
    @{{ Url = "$baseUrl/static/agent/Agent.ps1"; Path = (Join-Path $Config.AgentDir "Agent.ps1") }},
    @{{ Url = "$baseUrl/static/agent/modules/DscGitCore.psm1"; Path = (Join-Path $Config.AgentDir "modules\DscGitCore.psm1") }},
    @{{ Url = "$baseUrl/static/agent/modules/OpenTuneAdapter.psm1"; Path = (Join-Path $Config.AgentDir "modules\OpenTuneAdapter.psm1") }}
)

$downloadSuccess = $true
foreach ($item in $downloads) {{
    $fileName = Split-Path $item.Path -Leaf
    Write-Status "  Downloading $fileName..." -Type INFO
    if (-not (Download-File -Url $item.Url -OutPath $item.Path)) {{
        $downloadSuccess = $false
    }}
}}

if (-not $downloadSuccess) {{
    Write-Status "Some downloads failed. Please check network connectivity." -Type ERROR
    exit 1
}}
Write-Status "Agent components downloaded" -Type SUCCESS

# Step 4: Create scheduled task
Write-Status "Creating scheduled task..."
$agentPath = Join-Path $Config.AgentDir "Agent.ps1"
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$agentPath`""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date) -RepetitionInterval (New-TimeSpan -Minutes $Config.IntervalMin) -RepetitionDuration (New-TimeSpan -Days 9999)
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -RunOnlyIfNetworkAvailable

# Remove existing task if present
Unregister-ScheduledTask -TaskName $Config.TaskName -Confirm:$false -ErrorAction SilentlyContinue

Register-ScheduledTask -TaskName $Config.TaskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "OpenTune DSC reconciliation agent" | Out-Null

Write-Status "Scheduled task created (runs every $($Config.IntervalMin) minutes)" -Type SUCCESS

# Step 5: Run agent immediately
Write-Host ""
Write-Status "Running initial reconciliation..."
Write-Host "----------------------------------------"

try {{
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $agentPath
    Write-Host "----------------------------------------"
    Write-Status "Initial run completed" -Type SUCCESS
}}
catch {{
    Write-Host "----------------------------------------"
    Write-Status "Initial run failed: $($_.Exception.Message)" -Type WARN
    Write-Status "The scheduled task will retry automatically" -Type INFO
}}

# Done
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  Bootstrap Complete!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Status "Agent installed at: $($Config.AgentDir)"
Write-Status "Modules: $($Config.AgentDir)\modules\"
Write-Status "Config: $configPath"
Write-Status "Scheduled task: $($Config.TaskName)"
Write-Status "Interval: Every $($Config.IntervalMin) minutes"
Write-Host ""
'''


@router.get(
    "/nodes/{node_id}/bootstrap.ps1",
    response_class=PlainTextResponse,
    # NO admin API key required - authentication is via token query parameter
    # This allows direct download from browser or PowerShell without headers
)
def get_bootstrap_script(
    node_id: int,
    token: str,  # Token is provided as query param for authentication
    request: Request,
    session: Session = Depends(get_session),
):
    """
    Get the bootstrap script for a node.
    
    Authentication is via the `token` query parameter.
    This allows the script to be downloaded directly from a browser or via
    Invoke-WebRequest without needing to set HTTP headers.
    
    The token is validated against the node's stored hash.
    If valid, a PowerShell script is returned with the token embedded.
    
    Example:
        GET /api/v1/agents/nodes/1/bootstrap.ps1?token=abc123...
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    # Validate the token against the stored hash
    if not verify_token(token, node.node_token_hash):
        raise not_found("Node", node_id)  # Return 404 to not leak node existence
    
    server_url = get_server_url(request)
    
    script = BOOTSTRAP_SCRIPT_TEMPLATE.format(
        node_name=node.name,
        node_id=node.id,
        node_token=token,
        server_url=server_url,
    )
    
    return PlainTextResponse(
        content=script,
        media_type="text/plain; charset=utf-8",
        headers={
            "Content-Disposition": f'attachment; filename="bootstrap-{node.name}.ps1"',
        }
    )


# ============================================================================
# Static Agent Script Endpoint (fallback)
# ============================================================================

@router.get("/agent.ps1", include_in_schema=False)
def get_agent_script():
    """Redirect to static agent script."""
    from fastapi.responses import RedirectResponse
    return RedirectResponse(url="/static/agent/Agent.ps1")
