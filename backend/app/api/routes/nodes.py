"""
Node management routes.

Admin endpoints require X-Admin-API-Key header.
"""

from typing import List, Optional
from datetime import datetime, timedelta
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select

from app.core.db import get_session
from app.core.security import verify_admin_api_key, generate_node_token, hash_token
from app.core.exceptions import not_found, conflict, bad_request
from app.models import Node, Policy, ReconciliationRun
from app.schemas import (
    NodeRead,
    NodeCreate,
    NodeCreatedResponse,
    NodeAssignPolicy,
    RunRead,
)

router = APIRouter(prefix="/nodes", tags=["nodes"])


# ============================================================================
# Admin Endpoints (require API key)
# ============================================================================

@router.get(
    "/",
    response_model=List[NodeRead],
    dependencies=[Depends(verify_admin_api_key)],
)
def list_nodes(
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(100, ge=1, le=500, description="Maximum records to return"),
    status: Optional[str] = Query(None, description="Filter by last_status"),
    stale_hours: Optional[int] = Query(
        None,
        ge=1,
        description="Only show nodes not seen in the last N hours"
    ),
    session: Session = Depends(get_session),
):
    """
    List all registered nodes.
    
    Supports filtering by status and staleness.
    """
    statement = select(Node)
    
    if status is not None:
        statement = statement.where(Node.last_status == status)
    
    if stale_hours is not None:
        cutoff = datetime.utcnow() - timedelta(hours=stale_hours)
        statement = statement.where(
            (Node.last_seen_at == None) | (Node.last_seen_at < cutoff)
        )
    
    statement = statement.offset(skip).limit(limit)
    nodes = session.exec(statement).all()
    return nodes


@router.get(
    "/{node_id}",
    response_model=NodeRead,
    dependencies=[Depends(verify_admin_api_key)],
)
def get_node(
    node_id: int,
    session: Session = Depends(get_session),
):
    """
    Get a specific node by ID.
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    return node


@router.post(
    "/",
    response_model=NodeCreatedResponse,
    status_code=201,
    dependencies=[Depends(verify_admin_api_key)],
)
def create_node(
    node_in: NodeCreate,
    session: Session = Depends(get_session),
):
    """
    Create a new node and generate its authentication token.
    
    ⚠️ IMPORTANT: The token is returned ONLY in this response.
    Store it securely - it cannot be retrieved again!
    
    If you lose the token, delete the node and create a new one.
    """
    # Check for duplicate name
    existing = session.exec(
        select(Node).where(Node.name == node_in.name)
    ).first()
    if existing:
        raise conflict(f"Node with name '{node_in.name}' already exists")
    
    # Generate token
    plain_token = generate_node_token()
    hashed_token = hash_token(plain_token)
    
    # Create node
    node = Node(
        name=node_in.name,
        node_token_hash=hashed_token,
        last_status="registered",
    )
    session.add(node)
    session.commit()
    session.refresh(node)
    
    # Return node info with the plain token (shown only once)
    return NodeCreatedResponse(
        node=NodeRead.model_validate(node),
        token=plain_token,
    )


@router.delete(
    "/{node_id}",
    status_code=204,
    dependencies=[Depends(verify_admin_api_key)],
)
def delete_node(
    node_id: int,
    session: Session = Depends(get_session),
):
    """
    Delete a node.
    
    This also deletes all associated reconciliation runs.
    The agent will no longer be able to authenticate.
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    # Delete associated runs first (cascade would be better but keeping simple)
    runs = session.exec(
        select(ReconciliationRun).where(ReconciliationRun.node_id == node_id)
    ).all()
    for run in runs:
        session.delete(run)
    
    session.delete(node)
    session.commit()
    return None


@router.post(
    "/{node_id}/regenerate-token",
    response_model=NodeCreatedResponse,
    dependencies=[Depends(verify_admin_api_key)],
)
def regenerate_node_token(
    node_id: int,
    session: Session = Depends(get_session),
):
    """
    Regenerate the authentication token for a node.
    
    The old token is immediately invalidated.
    
    ⚠️ IMPORTANT: The new token is returned ONLY in this response.
    Update the agent configuration with the new token.
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    # Generate new token
    plain_token = generate_node_token()
    hashed_token = hash_token(plain_token)
    
    node.node_token_hash = hashed_token
    session.add(node)
    session.commit()
    session.refresh(node)
    
    return NodeCreatedResponse(
        node=NodeRead.model_validate(node),
        token=plain_token,
    )


@router.put(
    "/{node_id}/policy",
    response_model=NodeRead,
    dependencies=[Depends(verify_admin_api_key)],
)
def assign_policy_to_node(
    node_id: int,
    assignment: NodeAssignPolicy,
    session: Session = Depends(get_session),
):
    """
    Assign a policy to a node, or unassign (set policy_id to null).
    
    The agent will pick up the new policy on its next reconciliation cycle.
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    if assignment.policy_id is not None:
        # Verify policy exists
        policy = session.get(Policy, assignment.policy_id)
        if not policy:
            raise bad_request(f"Policy with id {assignment.policy_id} not found")
    
    node.assigned_policy_id = assignment.policy_id
    session.add(node)
    session.commit()
    session.refresh(node)
    
    return node


@router.get(
    "/{node_id}/runs",
    response_model=List[RunRead],
    dependencies=[Depends(verify_admin_api_key)],
)
def get_node_runs(
    node_id: int,
    skip: int = Query(0, ge=0),
    limit: int = Query(20, ge=1, le=100),
    session: Session = Depends(get_session),
):
    """
    Get reconciliation run history for a specific node.
    
    Results are ordered by started_at descending (most recent first).
    """
    node = session.get(Node, node_id)
    if not node:
        raise not_found("Node", node_id)
    
    from sqlmodel import desc
    runs = session.exec(
        select(ReconciliationRun)
        .where(ReconciliationRun.node_id == node_id)
        .order_by(desc(ReconciliationRun.started_at))
        .offset(skip)
        .limit(limit)
    ).all()
    
    return runs

