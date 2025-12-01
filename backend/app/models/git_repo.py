from typing import Optional, List
from sqlmodel import SQLModel, Field, Relationship

class GitRepository(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    url: str
    default_branch: str = "main"

    policies: List["Policy"] = Relationship(back_populates="git_repository")
