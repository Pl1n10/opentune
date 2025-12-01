"""Node schemas for API request/response validation."""

from datetime import datetime
from typing import Optional

from pydantic import BaseModel, Field, ConfigDict


class NodeBase(BaseModel):
    """Base schema for Node with common fields."""
    
    name: str = Field(
        ...,
        min_length=1,
        max_length=255,
        description="Unique name for the node (e.g., hostname)",
        examples=["pc-genitori", "server-web-01"],
    )


class NodeCreate(NodeBase):
    """
    Schema for creating a new node.
    
    The backend will generate a token automatically.
    """
    pass


class NodeRead(NodeBase):
    """Schema for reading node data (API responses)."""
    
    model_config = ConfigDict(from_attributes=True)
    
    id: int
    assigned_policy_id: Optional[int] = None
    last_seen_at: Optional[datetime] = None
    last_status: Optional[str] = Field(
        default="unknown",
        description="Last reported status: unknown, success, failed, in_progress, registered",
    )


class NodeReadWithPolicy(NodeRead):
    """Schema for reading node data including policy details."""
    
    assigned_policy_name: Optional[str] = None


class NodeCreatedResponse(BaseModel):
    """
    Response schema after creating a node.
    
    Includes the plaintext token - this is shown ONLY ONCE at creation time.
    """
    
    node: NodeRead = Field(
        ...,
        description="The created node details",
    )
    
    token: str = Field(
        ...,
        description="Node authentication token. SAVE THIS - it won't be shown again!",
    )


class NodeAssignPolicy(BaseModel):
    """Schema for assigning a policy to a node."""
    
    policy_id: Optional[int] = Field(
        None,
        description="Policy ID to assign, or null to unassign",
    )
