"""
Policy management routes.

These endpoints are admin-only and require X-Admin-API-Key header.
"""

from typing import List
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select

from app.core.db import get_session
from app.core.security import verify_admin_api_key
from app.core.exceptions import not_found, conflict, bad_request
from app.models import Policy, GitRepository, Node
from app.schemas import (
    PolicyCreate,
    PolicyRead,
    PolicyUpdate,
    PolicyReadWithRepo,
)

router = APIRouter(
    prefix="/policies",
    tags=["policies"],
    dependencies=[Depends(verify_admin_api_key)],
)


@router.get("/", response_model=List[PolicyReadWithRepo])
def list_policies(
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(100, ge=1, le=500, description="Maximum records to return"),
    session: Session = Depends(get_session),
):
    """
    List all policies with their repository information.
    
    Supports pagination with skip and limit parameters.
    """
    statement = select(Policy).offset(skip).limit(limit)
    policies = session.exec(statement).all()
    
    result = []
    for policy in policies:
        repo = session.get(GitRepository, policy.git_repository_id)
        policy_data = PolicyReadWithRepo.model_validate(policy)
        if repo:
            policy_data.repository_name = repo.name
            policy_data.repository_url = repo.url
        result.append(policy_data)
    
    return result


@router.get("/{policy_id}", response_model=PolicyReadWithRepo)
def get_policy(
    policy_id: int,
    session: Session = Depends(get_session),
):
    """
    Get a specific policy by ID with repository details.
    """
    policy = session.get(Policy, policy_id)
    if not policy:
        raise not_found("Policy", policy_id)
    
    repo = session.get(GitRepository, policy.git_repository_id)
    policy_data = PolicyReadWithRepo.model_validate(policy)
    if repo:
        policy_data.repository_name = repo.name
        policy_data.repository_url = repo.url
    
    return policy_data


@router.post("/", response_model=PolicyRead, status_code=201)
def create_policy(
    policy_in: PolicyCreate,
    session: Session = Depends(get_session),
):
    """
    Create a new policy.
    
    A policy defines:
    - Which Git repository to use
    - Which branch (optional, defaults to repo's default_branch)
    - Which config file path within the repo
    
    Example config_path values:
    - "nodes/server01.ps1" - DSC configuration script
    - "mof/server01" - Pre-compiled MOF directory
    """
    # Verify repository exists
    repo = session.get(GitRepository, policy_in.git_repository_id)
    if not repo:
        raise bad_request(f"GitRepository with id {policy_in.git_repository_id} not found")
    
    # Check for duplicate name
    existing = session.exec(
        select(Policy).where(Policy.name == policy_in.name)
    ).first()
    if existing:
        raise conflict(f"Policy with name '{policy_in.name}' already exists")
    
    policy = Policy.model_validate(policy_in)
    session.add(policy)
    session.commit()
    session.refresh(policy)
    return policy


@router.put("/{policy_id}", response_model=PolicyRead)
def update_policy(
    policy_id: int,
    policy_in: PolicyUpdate,
    session: Session = Depends(get_session),
):
    """
    Update a policy.
    
    Only provided fields will be updated.
    Note: git_repository_id cannot be changed after creation.
    """
    policy = session.get(Policy, policy_id)
    if not policy:
        raise not_found("Policy", policy_id)
    
    update_data = policy_in.model_dump(exclude_unset=True)
    
    # Check for name conflict if name is being updated
    if "name" in update_data and update_data["name"] != policy.name:
        existing = session.exec(
            select(Policy).where(Policy.name == update_data["name"])
        ).first()
        if existing:
            raise conflict(f"Policy with name '{update_data['name']}' already exists")
    
    for key, value in update_data.items():
        setattr(policy, key, value)
    
    session.add(policy)
    session.commit()
    session.refresh(policy)
    return policy


@router.delete("/{policy_id}", status_code=204)
def delete_policy(
    policy_id: int,
    force: bool = Query(False, description="Force delete even if nodes are assigned to this policy"),
    session: Session = Depends(get_session),
):
    """
    Delete a policy.
    
    By default, fails if any nodes are assigned to this policy.
    Use force=true to delete anyway (nodes will be unassigned).
    """
    policy = session.get(Policy, policy_id)
    if not policy:
        raise not_found("Policy", policy_id)
    
    # Check for assigned nodes
    nodes = session.exec(
        select(Node).where(Node.assigned_policy_id == policy_id)
    ).all()
    
    if nodes and not force:
        node_names = [n.name for n in nodes]
        preview = ', '.join(node_names[:5])
        suffix = '...' if len(node_names) > 5 else ''
        raise bad_request(
            f"Cannot delete policy: {len(nodes)} nodes are assigned to it "
            f"({preview}{suffix}). Use force=true to delete anyway."
        )
    
    # Unassign nodes if force delete
    if nodes and force:
        for node in nodes:
            node.assigned_policy_id = None
            session.add(node)
    
    session.delete(policy)
    session.commit()
    return None


@router.get("/{policy_id}/nodes")
def get_policy_nodes(
    policy_id: int,
    session: Session = Depends(get_session),
):
    """
    Get all nodes assigned to this policy.
    """
    
    policy = session.get(Policy, policy_id)
    if not policy:
        raise not_found("Policy", policy_id)
    
    nodes = session.exec(
        select(Node).where(Node.assigned_policy_id == policy_id)
    ).all()
    return nodes
