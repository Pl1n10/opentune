from typing import Optional, List
from sqlmodel import SQLModel, Field, Relationship

class Policy(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str

    git_repository_id: int = Field(foreign_key="gitrepository.id")
    branch: Optional[str] = None
    config_path: str

    git_repository: "GitRepository" = Relationship(back_populates="policies")
    nodes: List["Node"] = Relationship(back_populates="assigned_policy")
    runs: List["ReconciliationRun"] = Relationship(back_populates="policy")
