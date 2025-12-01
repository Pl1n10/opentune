from datetime import datetime
from typing import Optional, List
from sqlmodel import SQLModel, Field, Relationship

class Node(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str = Field(index=True)
    node_token_hash: str
    assigned_policy_id: Optional[int] = Field(default=None, foreign_key="policy.id")
    last_seen_at: Optional[datetime] = None
    last_status: Optional[str] = Field(default="unknown")

    assigned_policy: Optional["Policy"] = Relationship(back_populates="nodes")
    runs: List["ReconciliationRun"] = Relationship(back_populates="node")
