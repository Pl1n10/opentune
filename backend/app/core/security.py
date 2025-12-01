"""Security utilities: token hashing, authentication dependencies."""

import secrets
from typing import Annotated

import bcrypt
from fastapi import Depends, Header, HTTPException, status
from sqlmodel import Session

from .config import get_settings
from .db import get_session

settings = get_settings()


# =============================================================================
# Token Generation and Hashing (bcrypt)
# =============================================================================

def generate_node_token() -> str:
    """
    Generate a cryptographically secure random token for node authentication.
    
    Returns:
        A URL-safe base64 encoded string.
    """
    return secrets.token_urlsafe(settings.NODE_TOKEN_BYTES)


def hash_token(token: str) -> str:
    """
    Hash a token using bcrypt.
    
    Args:
        token: The plaintext token to hash.
        
    Returns:
        The bcrypt hash as a string.
    """
    # bcrypt expects bytes
    token_bytes = token.encode("utf-8")
    salt = bcrypt.gensalt(rounds=12)
    hashed = bcrypt.hashpw(token_bytes, salt)
    return hashed.decode("utf-8")


def verify_token(token: str, token_hash: str) -> bool:
    """
    Verify a token against its bcrypt hash.
    
    Args:
        token: The plaintext token to verify.
        token_hash: The bcrypt hash to verify against.
        
    Returns:
        True if the token matches the hash, False otherwise.
    """
    try:
        token_bytes = token.encode("utf-8")
        hash_bytes = token_hash.encode("utf-8")
        return bcrypt.checkpw(token_bytes, hash_bytes)
    except Exception:
        # Invalid hash format or other error
        return False


# =============================================================================
# Authentication Dependencies
# =============================================================================

def verify_admin_api_key(
    x_admin_api_key: Annotated[str, Header(alias="X-Admin-API-Key")]
) -> bool:
    """
    Dependency to verify the admin API key.
    
    Usage:
        @router.post("/", dependencies=[Depends(verify_admin_api_key)])
        def create_something():
            ...
    
    Raises:
        HTTPException 401 if the API key is missing or invalid.
    """
    if not secrets.compare_digest(x_admin_api_key, settings.ADMIN_API_KEY):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing Admin API Key",
            headers={"WWW-Authenticate": "ApiKey"},
        )
    return True


def get_node_by_token(
    node_id: int,
    x_node_token: Annotated[str, Header(alias="X-Node-Token")],
    session: Session = Depends(get_session),
):
    """
    Dependency to authenticate a node by its token.
    
    Usage:
        @router.get("/nodes/{node_id}/something")
        def get_something(node: Node = Depends(get_node_by_token)):
            ...
    
    Returns:
        The authenticated Node object.
        
    Raises:
        HTTPException 404 if node not found.
        HTTPException 401 if token is invalid.
    """
    from app.models import Node
    
    node = session.get(Node, node_id)
    if not node:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail="Node not found",
        )
    
    if not verify_token(x_node_token, node.node_token_hash):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid node token",
            headers={"WWW-Authenticate": "NodeToken"},
        )
    
    return node


# Type aliases for cleaner dependency injection
AdminAuth = Annotated[bool, Depends(verify_admin_api_key)]
