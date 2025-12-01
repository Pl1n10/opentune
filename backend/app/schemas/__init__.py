"""Pydantic schemas for API request/response validation."""

from .node import (
    NodeBase,
    NodeCreate,
    NodeRead,
    NodeReadWithPolicy,
    NodeCreatedResponse,
    NodeAssignPolicy,
)
from .git_repo import (
    GitRepositoryBase,
    GitRepositoryCreate,
    GitRepositoryUpdate,
    GitRepositoryRead,
    GitRepositoryReadWithStats,
)
from .policy import (
    PolicyBase,
    PolicyCreate,
    PolicyUpdate,
    PolicyRead,
    PolicyReadWithRepo,
    PolicyReadWithStats,
)
from .run import (
    RunStatus,
    RunReport,
    RunRead,
    RunReadWithDetails,
)

__all__ = [
    # Node
    "NodeBase",
    "NodeCreate",
    "NodeRead",
    "NodeReadWithPolicy",
    "NodeCreatedResponse",
    "NodeAssignPolicy",
    # GitRepository
    "GitRepositoryBase",
    "GitRepositoryCreate",
    "GitRepositoryUpdate",
    "GitRepositoryRead",
    "GitRepositoryReadWithStats",
    # Policy
    "PolicyBase",
    "PolicyCreate",
    "PolicyUpdate",
    "PolicyRead",
    "PolicyReadWithRepo",
    "PolicyReadWithStats",
    # Run
    "RunStatus",
    "RunReport",
    "RunRead",
    "RunReadWithDetails",
]
