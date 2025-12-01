"""ReconciliationRun schemas for API request/response validation."""

from datetime import datetime
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict


class RunStatus(str, Enum):
    """Valid status values for reconciliation runs."""
    
    SUCCESS = "success"
    FAILED = "failed"
    IN_PROGRESS = "in_progress"
    SKIPPED = "skipped"


class RunReport(BaseModel):
    """
    Schema for agents to report a reconciliation run.
    
    Sent by the agent after completing a DSC configuration cycle.
    """
    
    policy_id: int = Field(
        ...,
        gt=0,
        description="ID of the policy that was applied",
    )
    
    git_commit: Optional[str] = Field(
        default=None,
        min_length=7,
        max_length=40,
        description="Git commit SHA that was used",
        examples=["a1b2c3d", "a1b2c3d4e5f6g7h8i9j0k1l2m3n4o5p6q7r8s9t0"],
    )
    
    status: RunStatus = Field(
        ...,
        description="Outcome of the DSC run",
    )
    
    summary: Optional[str] = Field(
        default=None,
        max_length=4096,
        description="Human-readable summary or error message",
    )
    
    started_at: Optional[datetime] = Field(
        default=None,
        description="When the run started (if not provided, uses current time)",
    )
    
    finished_at: Optional[datetime] = Field(
        default=None,
        description="When the run finished (if not provided, uses current time)",
    )


class RunRead(BaseModel):
    """Schema for reading ReconciliationRun data (API responses)."""
    
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    node_id: int
    policy_id: int
    git_commit: Optional[str] = None
    started_at: datetime
    finished_at: Optional[datetime] = None
    status: str
    summary: Optional[str] = None


class RunReadWithDetails(RunRead):
    """Schema including node and policy names."""
    
    node_name: Optional[str] = None
    policy_name: Optional[str] = None
