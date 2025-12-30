"""
OpenTune (dsc-cp) - GitOps Control Plane for Windows DSC

Main application entry point.
"""

import os
from contextlib import asynccontextmanager
from pathlib import Path

from fastapi import FastAPI, Request
from fastapi.middleware.cors import CORSMiddleware
from fastapi.staticfiles import StaticFiles
from fastapi.responses import FileResponse, JSONResponse
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

from app.core.config import get_settings
from app.core.db import init_db
from app.api import api_router

settings = get_settings()

# Rate limiter - use IP address as key
limiter = Limiter(key_func=get_remote_address, default_limits=["100/minute"])


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


def find_static_dir() -> Path | None:
    """Find the static files directory (for agent scripts etc.)."""
    candidates = [
        Path(__file__).parent.parent / "static",  # Development
        Path(__file__).parent / "static",  # Alternative dev
        Path("/app/backend/static"),  # Docker
        Path("/app/static"),  # Docker alternative
    ]
    
    for path in candidates:
        if path.exists():
            return path
    
    return None


def check_security_config():
    """Check for insecure configuration on startup."""
    import sys
    import logging
    
    logger = logging.getLogger("opentune.security")
    
    # Check for default API key
    default_keys = [
        "CHANGE-ME-GENERATE-A-SECURE-KEY",
        "changeme",
        "admin",
        "password",
        "secret",
        "test",
    ]
    
    if settings.ADMIN_API_KEY.lower() in [k.lower() for k in default_keys]:
        logger.critical(
            "\n"
            "╔═══════════════════════════════════════════════════════════════╗\n"
            "║  SECURITY ERROR: Default API key detected!                    ║\n"
            "║                                                               ║\n"
            "║  Set a secure ADMIN_API_KEY environment variable:             ║\n"
            "║                                                               ║\n"
            "║  python -c \"import secrets; print(secrets.token_urlsafe(32))\"  ║\n"
            "║                                                               ║\n"
            "║  Then set: ADMIN_API_KEY=<your-generated-key>                 ║\n"
            "╚═══════════════════════════════════════════════════════════════╝"
        )
        if not settings.DEBUG:
            sys.exit(1)
        else:
            logger.warning("Continuing with insecure key because DEBUG=True")
    
    # Check API key length
    if len(settings.ADMIN_API_KEY) < 32:
        logger.warning(
            "ADMIN_API_KEY is less than 32 characters. "
            "Consider using a longer key for better security."
        )


FRONTEND_DIR = find_frontend_dir()
STATIC_DIR = find_static_dir()


@asynccontextmanager
async def lifespan(app: FastAPI):
    """Application lifecycle management."""
    # Startup
    check_security_config()
    init_db()
    yield
    # Shutdown (cleanup if needed)


def get_cors_origins() -> list:
    """Get allowed CORS origins based on configuration."""
    if settings.DEBUG:
        # Development: allow all
        return ["*"]
    
    # Production: restrict to known origins
    origins = ["https://opentune.robertonovara.dev"]
    
    # Add SERVER_URL if configured
    if settings.SERVER_URL:
        origins.append(settings.SERVER_URL.rstrip("/"))
    
    return origins


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
        docs_url="/api/docs" if settings.DEBUG else None,  # Disable in prod
        redoc_url="/api/redoc" if settings.DEBUG else None,
        openapi_url="/api/openapi.json" if settings.DEBUG else None,
    )
    
    # CORS - restricted in production
    cors_origins = get_cors_origins()
    app.add_middleware(
        CORSMiddleware,
        allow_origins=cors_origins,
        allow_credentials=True,
        allow_methods=["GET", "POST", "PUT", "DELETE", "PATCH"],
        allow_headers=["X-Admin-API-Key", "X-Node-Token", "Content-Type"],
    )
    
    # Rate limiting
    app.state.limiter = limiter
    app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
    
    # Security headers middleware
    @app.middleware("http")
    async def add_security_headers(request: Request, call_next):
        response = await call_next(request)
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        if not settings.DEBUG:
            response.headers["Strict-Transport-Security"] = "max-age=31536000; includeSubDomains"
        return response
    
    # API routes
    app.include_router(api_router, prefix=settings.API_V1_STR)
    
    # Serve static files (agent scripts etc.)
    if STATIC_DIR:
        app.mount("/static", StaticFiles(directory=STATIC_DIR), name="static")
    
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
