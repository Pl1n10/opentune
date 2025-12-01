"""API router aggregation."""

from fastapi import APIRouter
from .routes import nodes, agents, git_repos, policies, runs

api_router = APIRouter()

# Admin endpoints
api_router.include_router(nodes.router)
api_router.include_router(git_repos.router)
api_router.include_router(policies.router)
api_router.include_router(runs.router)

# Agent endpoints
api_router.include_router(agents.router)
