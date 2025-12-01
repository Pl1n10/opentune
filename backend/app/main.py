"""
OpenTune (dsc-cp) - GitOps Control Plane for Windows DSC

Main application entry point.
"""

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse

from app.core.config import get_settings
from app.core.db import init_db
from app.api import api_router

settings = get_settings()


def find_frontend_dir() -> Path | None:
    """Find the frontend dist directory."""
    # Possible locations
    candidates = [
        Path(__file__).parent.parent / "frontend" / "dist",  # Development
        Path(__file__).parent.parent.parent / "frontend" / "dist",  # Also dev
        Path("/app/frontend/dist"),  # Docker
    ]
    
    for path in candidates:
        if path.exists() and (path / "index.html").exists():
            return path
    
    return None


FRONTEND_DIR = find_frontend_dir()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle management."""
    # Startup
    init_db()
    yield
    # Shutdown (cleanup if needed)


def create_app() -> FastAPI:
    """Create and configure the FastAPI application."""
    
    app = FastAPI(
        title=settings.PROJECT_NAME,
        description="""
## GitOps Control Plane for Windows DSC

**OpenTune** is a self-hosted GitOps control plane for managing Windows 
configurations using PowerShell Desired State Configuration (DSC).

### Key Concepts

- **Git is the source of truth** - All configurations are stored in Git repositories
- **Pull-based model** - Agents pull their desired state, no push commands
- **Self-healing** - Nodes automatically remediate configuration drift

### Authentication

- **Admin endpoints** (`/nodes`, `/policies`, `/repositories`, `/runs`): 
  Require `X-Admin-API-Key` header
- **Agent endpoints** (`/agents/*`): 
  Require `X-Node-Token` header with the node's unique token
        """,
        version="0.2.0",
        lifespan=lifespan,
        docs_url="/api/docs",
        redoc_url="/api/redoc",
        openapi_url="/api/openapi.json",
    )
    
    # CORS
    app.add_middleware(
        CORSMiddleware,
        allow_origins=["*"],
        allow_credentials=True,
        allow_methods=["*"],
        allow_headers=["*"],
    )
    
    # API routes
    app.include_router(api_router, prefix=settings.API_V1_STR)
    
    # Health check
    @app.get("/health", tags=["health"])
    def health_check():
        """Health check endpoint for monitoring."""
        return {"status": "healthy"}
    
    # Serve frontend if available
    if FRONTEND_DIR:
        # Serve static assets
        if (FRONTEND_DIR / "assets").exists():
            app.mount(
                "/assets", 
                StaticFiles(directory=FRONTEND_DIR / "assets"), 
                name="assets"
            )
        
        # Serve other static files (favicon, etc.)
        @app.get("/favicon.svg")
        async def favicon():
            favicon_path = FRONTEND_DIR / "favicon.svg"
            if favicon_path.exists():
                return FileResponse(favicon_path)
            return {"detail": "Not found"}
        
        # SPA catch-all route
        @app.get("/{full_path:path}")
        async def serve_spa(full_path: str):
            # Don't catch API routes
            if full_path.startswith("api/") or full_path == "health":
                return {"detail": "Not found"}
            
            # Serve static file if exists
            file_path = FRONTEND_DIR / full_path
            if file_path.is_file():
                return FileResponse(file_path)
            
            # Otherwise serve index.html (SPA routing)
            return FileResponse(FRONTEND_DIR / "index.html")
    else:
        # No frontend - show API info at root
        @app.get("/", tags=["health"])
        def root():
            return {
                "name": settings.PROJECT_NAME,
                "version": "0.2.0",
                "api_docs": "/api/docs",
                "note": "Frontend not found. Build it with 'npm run build' in frontend/",
            }
    
    return app


app = create_app()
