"""
Reconciliation Run routes.

Read-only endpoints for viewing run history.
Admin-only access.
"""

from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select, desc

from app.core.db import get_session
from app.core.security import verify_admin_api_key
from app.core.exceptions import not_found
from app.models import ReconciliationRun, Node, Policy
from app.schemas import RunRead, RunReadWithDetails

router = APIRouter(
    prefix="/runs",
    tags=["runs"],
    dependencies=[Depends(verify_admin_api_key)],
)


@router.get("/", response_model=List[RunReadWithDetails])
def list_runs(
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(50, ge=1, le=200, description="Maximum records to return"),
    node_id: Optional[int] = Query(None, description="Filter by node ID"),
    policy_id: Optional[int] = Query(None, description="Filter by policy ID"),
    status: Optional[str] = Query(None, description="Filter by status"),
    since: Optional[datetime] = Query(None, description="Only runs after this time"),
    session: Session = Depends(get_session),
):
    """
    List reconciliation runs with optional filters.
    
    Results are ordered by started_at descending (most recent first).
    """
    statement = select(ReconciliationRun)
    
    if node_id is not None:
        statement = statement.where(ReconciliationRun.node_id == node_id)
    if policy_id is not None:
        statement = statement.where(ReconciliationRun.policy_id == policy_id)
    if status is not None:
        statement = statement.where(ReconciliationRun.status == status)
    if since is not None:
        statement = statement.where(ReconciliationRun.started_at >= since)
    
    statement = statement.order_by(desc(ReconciliationRun.started_at))
    statement = statement.offset(skip).limit(limit)
    
    runs = session.exec(statement).all()
    
    # Enrich with node/policy names
    result = []
    for run in runs:
        run_data = RunReadWithDetails.model_validate(run)
        node = session.get(Node, run.node_id)
        policy = session.get(Policy, run.policy_id)
        if node:
            run_data.node_name = node.name
        if policy:
            run_data.policy_name = policy.name
        result.append(run_data)
    
    return result


@router.get("/stats")
def get_run_stats(
    hours: int = Query(24, ge=1, le=168, description="Hours to look back"),
    session: Session = Depends(get_session),
):
    """
    Get aggregated statistics for runs in the last N hours.
    
    Returns counts by status, success rate, etc.
    """
    since = datetime.utcnow() - timedelta(hours=hours)
    
    runs = session.exec(
        select(ReconciliationRun).where(ReconciliationRun.started_at >= since)
    ).all()
    
    total = len(runs)
    by_status = {}
    for run in runs:
        by_status[run.status] = by_status.get(run.status, 0) + 1
    
    success_count = by_status.get("success", 0)
    success_rate = (success_count / total * 100) if total > 0 else 0.0
    
    # Find unique nodes that reported
    unique_nodes = set(run.node_id for run in runs)
    
    return {
        "period_hours": hours,
        "total_runs": total,
        "by_status": by_status,
        "success_rate_percent": round(success_rate, 1),
        "unique_nodes_reporting": len(unique_nodes),
    }


@router.get("/{run_id}", response_model=RunReadWithDetails)
def get_run(
    run_id: int,
    session: Session = Depends(get_session),
):
    """
    Get a specific run by ID with node and policy details.
    """
    run = session.get(ReconciliationRun, run_id)
    if not run:
        raise not_found("ReconciliationRun", run_id)
    
    run_data = RunReadWithDetails.model_validate(run)
    node = session.get(Node, run.node_id)
    policy = session.get(Policy, run.policy_id)
    if node:
        run_data.node_name = node.name
    if policy:
        run_data.policy_name = policy.name
    
    return run_data
