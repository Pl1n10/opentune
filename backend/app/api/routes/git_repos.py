"""
Git Repository management routes.

These endpoints are admin-only and require X-Admin-API-Key header.
"""

from typing import List
from fastapi import APIRouter, Depends, Query
from sqlmodel import Session, select

from app.core.db import get_session
from app.core.security import verify_admin_api_key
from app.core.exceptions import not_found, conflict, bad_request
from app.models import GitRepository, Policy
from app.schemas import GitRepositoryCreate, GitRepositoryRead, GitRepositoryUpdate

router = APIRouter(
    prefix="/repositories",
    tags=["repositories"],
    dependencies=[Depends(verify_admin_api_key)],
)


@router.get("/", response_model=List[GitRepositoryRead])
def list_repositories(
    skip: int = Query(0, ge=0, description="Number of records to skip"),
    limit: int = Query(100, ge=1, le=500, description="Maximum records to return"),
    session: Session = Depends(get_session),
):
    """
    List all Git repositories.
    
    Supports pagination with skip and limit parameters.
    """
    statement = select(GitRepository).offset(skip).limit(limit)
    repos = session.exec(statement).all()
    return repos


@router.get("/{repo_id}", response_model=GitRepositoryRead)
def get_repository(
    repo_id: int,
    session: Session = Depends(get_session),
):
    """
    Get a specific Git repository by ID.
    """
    repo = session.get(GitRepository, repo_id)
    if not repo:
        raise not_found("GitRepository", repo_id)
    return repo


@router.post("/", response_model=GitRepositoryRead, status_code=201)
def create_repository(
    repo_in: GitRepositoryCreate,
    session: Session = Depends(get_session),
):
    """
    Create a new Git repository.
    
    The repository URL should be accessible by the agents (HTTPS with optional PAT in URL).
    """
    # Check for duplicate name
    existing = session.exec(
        select(GitRepository).where(GitRepository.name == repo_in.name)
    ).first()
    if existing:
        raise conflict(f"Repository with name '{repo_in.name}' already exists")
    
    # Check for duplicate URL
    existing_url = session.exec(
        select(GitRepository).where(GitRepository.url == repo_in.url)
    ).first()
    if existing_url:
        raise conflict(f"Repository with URL '{repo_in.url}' already exists")
    
    repo = GitRepository.model_validate(repo_in)
    session.add(repo)
    session.commit()
    session.refresh(repo)
    return repo


@router.put("/{repo_id}", response_model=GitRepositoryRead)
def update_repository(
    repo_id: int,
    repo_in: GitRepositoryUpdate,
    session: Session = Depends(get_session),
):
    """
    Update a Git repository.
    
    Only provided fields will be updated.
    """
    repo = session.get(GitRepository, repo_id)
    if not repo:
        raise not_found("GitRepository", repo_id)
    
    update_data = repo_in.model_dump(exclude_unset=True)
    
    # Check for name conflict if name is being updated
    if "name" in update_data and update_data["name"] != repo.name:
        existing = session.exec(
            select(GitRepository).where(GitRepository.name == update_data["name"])
        ).first()
        if existing:
            raise conflict(f"Repository with name '{update_data['name']}' already exists")
    
    # Check for URL conflict if URL is being updated
    if "url" in update_data and update_data["url"] != repo.url:
        existing = session.exec(
            select(GitRepository).where(GitRepository.url == update_data["url"])
        ).first()
        if existing:
            raise conflict(f"Repository with URL '{update_data['url']}' already exists")
    
    for key, value in update_data.items():
        setattr(repo, key, value)
    
    session.add(repo)
    session.commit()
    session.refresh(repo)
    return repo


@router.delete("/{repo_id}", status_code=204)
def delete_repository(
    repo_id: int,
    force: bool = Query(False, description="Force delete even if policies reference this repo"),
    session: Session = Depends(get_session),
):
    """
    Delete a Git repository.
    
    By default, fails if any policies reference this repository.
    Use force=true to delete anyway (policies will become orphaned).
    """
    repo = session.get(GitRepository, repo_id)
    if not repo:
        raise not_found("GitRepository", repo_id)
    
    # Check for referencing policies
    policies = session.exec(
        select(Policy).where(Policy.git_repository_id == repo_id)
    ).all()
    
    if policies and not force:
        policy_names = [p.name for p in policies]
        preview = ', '.join(policy_names[:5])
        suffix = '...' if len(policy_names) > 5 else ''
        raise bad_request(
            f"Cannot delete repository: {len(policies)} policies reference it "
            f"({preview}{suffix}). Use force=true to delete anyway."
        )
    
    session.delete(repo)
    session.commit()
    return None


@router.get("/{repo_id}/policies", response_model=List["PolicyRead"])
def get_repository_policies(
    repo_id: int,
    session: Session = Depends(get_session),
):
    """
    Get all policies that use this repository.
    """
    from app.schemas import PolicyRead  # Import here to avoid circular
    
    repo = session.get(GitRepository, repo_id)
    if not repo:
        raise not_found("GitRepository", repo_id)
    
    policies = session.exec(
        select(Policy).where(Policy.git_repository_id == repo_id)
    ).all()
    return policies
