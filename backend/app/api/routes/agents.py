"""
Agent communication routes.

These endpoints are used by the dsc-cp agent running on Windows nodes.
Authentication is via X-Node-Token header.
"""

from datetime import datetime
from typing import Optional
from fastapi import APIRouter, Depends, Header
from sqlmodel import Session
from pydantic import BaseModel

from app.core.db import get_session
from app.core.security import verify_token
from app.core.exceptions import not_found, unauthorized, bad_request
from app.models import Node, Policy, GitRepository, ReconciliationRun
from app.schemas import RunReport

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


# ============================================================================
# Agent Endpoints
# ============================================================================

@router.get("/nodes/{node_id}/desired-state", response_model=DesiredStateResponse)
def get_desired_state(
    node_id: int,
    x_node_token: str = Header(..., alias="X-Node-Token"),
    session: Session = Depends(get_session),
):
    """
    Get the desired state for a node.
    
    Called by the agent to determine what configuration to apply.
    Returns repository URL, branch, and config path if a policy is assigned.
    
    The agent should:
    1. Clone/pull the repository
    2. Checkout the specified branch
    3. Execute the DSC configuration at config_path
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
        # Policy was deleted but node still references it
        return DesiredStateResponse(policy_assigned=False)
    
    repo = session.get(GitRepository, policy.git_repository_id)
    if not repo:
        # Repository was deleted
        return DesiredStateResponse(policy_assigned=False)
    
    return DesiredStateResponse(
        policy_assigned=True,
        policy_id=policy.id,
        policy_name=policy.name,
        repository={
            "url": repo.url,
            "branch": policy.branch or repo.default_branch,
        },
        config_path=policy.config_path,
    )


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

