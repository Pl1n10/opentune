"""Database configuration and session management."""

from sqlmodel import SQLModel, create_engine, Session
from .config import get_settings

settings = get_settings()

# Create engine with appropriate settings
connect_args = {}
if settings.DATABASE_URL.startswith("sqlite"):
    # SQLite-specific: allow same connection across threads
    connect_args["check_same_thread"] = False

engine = create_engine(
    settings.DATABASE_URL,
    connect_args=connect_args,
    echo=settings.DEBUG,  # Log SQL queries in debug mode
)


def init_db() -> None:
    """Initialize database tables."""
    # Import all models to ensure they're registered with SQLModel
    from app.models import Node, GitRepository, Policy, ReconciliationRun  # noqa: F401
    
    SQLModel.metadata.create_all(bind=engine)


def get_session():
    """
    Dependency that provides a database session.
    
    Usage:
        @app.get("/")
        def endpoint(session: Session = Depends(get_session)):
            ...
    """
    with Session(engine) as session:
        yield session
