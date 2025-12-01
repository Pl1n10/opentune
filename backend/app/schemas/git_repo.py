"""GitRepository schemas for API request/response validation."""

from typing import Optional

from pydantic import BaseModel, Field, ConfigDict, field_validator
import re


class GitRepositoryBase(BaseModel):
    """Base schema for GitRepository with common fields."""
    
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Human-readable name for the repository",
        examples=["dsc-baseline-security", "company-dsc-configs"],
    )
    
    url: str = Field(
        ...,
        min_length=1,
        max_length=2048,
        description="Git repository URL (HTTPS). Can include PAT for private repos.",
        examples=[
            "https://github.com/example/dsc-configs.git",
            "https://user:token@github.com/example/private-dsc.git",
        ],
    )
    
    default_branch: str = Field(
        default="main",
        min_length=1,
        max_length=255,
        description="Default branch to use when policy doesn't specify one",
        examples=["main", "master", "production"],
    )
    
    @field_validator("url")
    @classmethod
    def validate_git_url(cls, v: str) -> str:
        """Validate that the URL is a valid Git HTTPS URL."""
        # Basic validation for HTTPS git URLs
        if not v.startswith(("https://", "http://")):
            raise ValueError("Git URL must start with https:// or http://")
        
        # Check for common git hosting patterns or .git suffix
        git_patterns = [
            r"github\.com",
            r"gitlab\.com", 
            r"bitbucket\.org",
            r"dev\.azure\.com",
            r"\.git$",
        ]
        if not any(re.search(pattern, v) for pattern in git_patterns):
            # Allow any URL but warn it might not be a git repo
            pass  # We'll allow it, git clone will fail if invalid
        
        return v


class GitRepositoryCreate(GitRepositoryBase):
    """Schema for creating a new GitRepository."""
    pass


class GitRepositoryUpdate(BaseModel):
    """Schema for updating an existing GitRepository (partial updates)."""
    
    name: Optional[str] = Field(
        None,
        min_length=1,
        max_length=255,
    )
    
    url: Optional[str] = Field(
        None,
        min_length=1,
        max_length=2048,
    )
    
    default_branch: Optional[str] = Field(
        None,
        min_length=1,
        max_length=255,
    )
    
    @field_validator("url")
    @classmethod
    def validate_git_url(cls, v: Optional[str]) -> Optional[str]:
        """Validate that the URL is a valid Git HTTPS URL if provided."""
        if v is None:
            return v
        if not v.startswith(("https://", "http://")):
            raise ValueError("Git URL must start with https:// or http://")
        return v


class GitRepositoryRead(GitRepositoryBase):
    """Schema for reading GitRepository data (API responses)."""
    
    model_config = ConfigDict(from_attributes=True)
    
    id: int


class GitRepositoryReadWithStats(GitRepositoryRead):
    """Schema including usage statistics."""
    
    policies_count: int = Field(
        default=0,
        description="Number of policies using this repository",
    )
