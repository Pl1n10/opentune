from datetime import datetime
from typing import Optional
from sqlmodel import SQLModel, Field, Relationship

class ReconciliationRun(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)

    node_id: int = Field(foreign_key="node.id")
    policy_id: int = Field(foreign_key="policy.id")

    git_commit: Optional[str] = None
    started_at: datetime = Field(default_factory=datetime.utcnow)
    finished_at: Optional[datetime] = None
    status: str
    summary: Optional[str] = None

    node: "Node" = Relationship(back_populates="runs")
    policy: "Policy" = Relationship(back_populates="runs")
