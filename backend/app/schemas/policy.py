"""Policy schemas for API request/response validation."""

from typing import Optional

from pydantic import BaseModel, Field, ConfigDict, field_validator


class PolicyBase(BaseModel):
    """Base schema for Policy with common fields."""
    
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Human-readable name for the policy",
        examples=["security-baseline", "workstation-standard"],
    )
    
    git_repository_id: int = Field(
        ...,
        gt=0,
        description="ID of the GitRepository containing the DSC configuration",
    )
    
    config_path: str = Field(
        ...,
        min_length=1,
        max_length=1024,
        description="Path to the DSC config file/directory relative to repo root",
        examples=["nodes/pc-genitori.ps1", "mof/server-baseline/"],
    )
    
    branch: Optional[str] = Field(
        default=None,
        max_length=255,
        description="Git branch to use. If null, uses repository's default_branch",
        examples=["main", "production", "feature/new-baseline"],
    )
    
    @field_validator("config_path")
    @classmethod
    def validate_config_path(cls, v: str) -> str:
        """Validate config_path is a reasonable path."""
        # Prevent path traversal
        if ".." in v:
            raise ValueError("config_path cannot contain '..' (path traversal)")
        
        # Remove leading slash if present
        v = v.lstrip("/")
        
        return v


class PolicyCreate(PolicyBase):
    """Schema for creating a new Policy."""
    pass


class PolicyUpdate(BaseModel):
    """Schema for updating an existing Policy (partial updates)."""
    
    name: Optional[str] = Field(
        None,
        min_length=1,
        max_length=255,
    )
    
    git_repository_id: Optional[int] = Field(
        None,
        gt=0,
    )
    
    config_path: Optional[str] = Field(
        None,
        min_length=1,
        max_length=1024,
    )
    
    branch: Optional[str] = Field(
        default=None,
        max_length=255,
    )
    
    @field_validator("config_path")
    @classmethod
    def validate_config_path(cls, v: Optional[str]) -> Optional[str]:
        """Validate config_path if provided."""
        if v is None:
            return v
        if ".." in v:
            raise ValueError("config_path cannot contain '..' (path traversal)")
        return v.lstrip("/")


class PolicyRead(PolicyBase):
    """Schema for reading Policy data (API responses)."""
    
    model_config = ConfigDict(from_attributes=True)
    
    id: int


class PolicyReadWithRepo(PolicyRead):
    """Schema including repository details."""
    
    repository_name: Optional[str] = None
    repository_url: Optional[str] = None


class PolicyReadWithStats(PolicyRead):
    """Schema including usage statistics."""
    
    nodes_count: int = Field(
        default=0,
        description="Number of nodes assigned to this policy",
    )
