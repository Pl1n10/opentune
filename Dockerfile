# =============================================================================
# OpenTune - Multi-stage Dockerfile
# =============================================================================
# Stage 1: Build frontend
# Stage 2: Python runtime with built frontend
# =============================================================================

# -----------------------------------------------------------------------------
# Stage 1: Build Frontend
# -----------------------------------------------------------------------------
FROM node:20-alpine AS frontend-builder

WORKDIR /app/frontend

# Copy package files first (better caching)
COPY frontend/package*.json ./

# Install dependencies
RUN npm ci --no-audit --no-fund

# Copy frontend source
COPY frontend/ ./

# Build for production
RUN npm run build

# -----------------------------------------------------------------------------
# Stage 2: Python Runtime
# -----------------------------------------------------------------------------
FROM python:3.11-slim

# Labels
LABEL org.opencontainers.image.title="OpenTune"
LABEL org.opencontainers.image.description="GitOps Control Plane for Windows DSC"
LABEL org.opencontainers.image.version="1.0.0"

# Environment
ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1

WORKDIR /app

# Install system dependencies (including git for server-side cloning)
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    git \
    && rm -rf /var/lib/apt/lists/*

# Copy and install Python dependencies
COPY backend/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy backend code
COPY backend/app ./app

# Copy static files (agent scripts)
COPY backend/static ./static

# Copy built frontend from stage 1
COPY --from=frontend-builder /app/frontend/dist ./frontend/dist

# Create non-root user and directories
RUN useradd --create-home --shell /bin/bash appuser && \
    mkdir -p /app/data /app/data/repos && \
    chown -R appuser:appuser /app

# Switch to non-root user
USER appuser

# Default environment variables
ENV PROJECT_NAME=opentune \
    DATABASE_URL=sqlite:///./data/opentune.db \
    ADMIN_API_KEY=CHANGE-ME-ON-FIRST-RUN \
    REPOS_DIR=/app/data/repos

# Expose port
EXPOSE 8000

# Health check
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

# Run the application
CMD ["uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
