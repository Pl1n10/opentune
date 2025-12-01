"""Application configuration loaded from environment variables."""

from pydantic_settings import BaseSettings, SettingsConfigDict
from functools import lru_cache


class Settings(BaseSettings):
    """
    Application settings.
    
    All settings can be overridden via environment variables or .env file.
    """
    
    model_config = SettingsConfigDict(
        env_file=".env",
        env_file_encoding="utf-8",
        case_sensitive=True,
        extra="ignore",
    )
    
    # Application
    PROJECT_NAME: str = "dsc-cp"
    API_V1_STR: str = "/api/v1"
    DEBUG: bool = False
    
    # Database
    DATABASE_URL: str = "sqlite:///./dsc_cp.db"
    
    # Security - Admin API key for management endpoints
    # Generate with: python -c "import secrets; print(secrets.token_urlsafe(32))"
    ADMIN_API_KEY: str = "CHANGE-ME-GENERATE-A-SECURE-KEY"
    
    # Token settings
    NODE_TOKEN_BYTES: int = 32  # Length of generated node tokens (results in 64 hex chars)


@lru_cache
def get_settings() -> Settings:
    """Get cached application settings."""
    return Settings()
