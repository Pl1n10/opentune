"""
Custom exceptions and error handlers for dsc-cp.
"""

from fastapi import HTTPException, status


class DscCpException(Exception):
    """Base exception for dsc-cp."""
    pass


class EntityNotFoundError(DscCpException):
    """Raised when a requested entity is not found."""
    def __init__(self, entity_type: str, entity_id: int | str):
        self.entity_type = entity_type
        self.entity_id = entity_id
        super().__init__(f"{entity_type} with id {entity_id} not found")


class AuthenticationError(DscCpException):
    """Raised when authentication fails."""
    pass


class ValidationError(DscCpException):
    """Raised when validation fails."""
    pass


# ============================================================================
# HTTP Exception Helpers
# ============================================================================

def not_found(entity_type: str, entity_id: int | str) -> HTTPException:
    """Return a 404 HTTPException for a missing entity."""
    return HTTPException(
        status_code=status.HTTP_404_NOT_FOUND,
        detail=f"{entity_type} with id '{entity_id}' not found"
    )


def bad_request(detail: str) -> HTTPException:
    """Return a 400 HTTPException."""
    return HTTPException(
        status_code=status.HTTP_400_BAD_REQUEST,
        detail=detail
    )


def unauthorized(detail: str = "Invalid credentials") -> HTTPException:
    """Return a 401 HTTPException."""
    return HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail=detail
    )


def conflict(detail: str) -> HTTPException:
    """Return a 409 HTTPException for conflicts (e.g., duplicate names)."""
    return HTTPException(
        status_code=status.HTTP_409_CONFLICT,
        detail=detail
    )


def internal_error(detail: str = "Internal server error") -> HTTPException:
    """Return a 500 HTTPException."""
    return HTTPException(
        status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
        detail=detail
    )
