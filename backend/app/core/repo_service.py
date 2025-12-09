"""
Repository Service - Server-side Git cloning and ZIP packaging.

This service manages Git repositories on the server side so that
Windows agents don't need Git installed.
"""

import os
import subprocess
import shutil
import tempfile
import zipfile
import hashlib
from pathlib import Path
from datetime import datetime
from typing import Optional, Tuple
import logging

from .config import get_settings

settings = get_settings()
logger = logging.getLogger(__name__)

# Default repos storage path
REPOS_BASE_DIR = Path(os.environ.get("REPOS_DIR", "/app/data/repos"))


class RepoServiceError(Exception):
    """Exception raised for repository service errors."""
    pass


def get_repo_path(repo_id: int) -> Path:
    """Get the local path for a repository."""
    return REPOS_BASE_DIR / str(repo_id)


def ensure_repos_dir():
    """Ensure the repos base directory exists."""
    REPOS_BASE_DIR.mkdir(parents=True, exist_ok=True)


def clone_or_update_repo(
    repo_id: int,
    repo_url: str,
    branch: str = "main"
) -> Tuple[str, bool]:
    """
    Clone a repository if it doesn't exist, or update it if it does.
    
    Returns:
        Tuple of (commit_hash, was_updated)
    
    Raises:
        RepoServiceError: If the operation fails.
    """
    ensure_repos_dir()
    repo_path = get_repo_path(repo_id)
    git_dir = repo_path / ".git"
    was_updated = False
    
    try:
        if not git_dir.exists():
            # Clone the repository
            logger.info(f"Cloning repository {repo_id} from {_sanitize_url(repo_url)}")
            
            result = subprocess.run(
                ["git", "clone", "--quiet", "--branch", branch, repo_url, str(repo_path)],
                capture_output=True,
                text=True,
                timeout=300,  # 5 minute timeout
            )
            
            if result.returncode != 0:
                raise RepoServiceError(f"Git clone failed: {result.stderr}")
            
            was_updated = True
        else:
            # Update the repository
            logger.info(f"Updating repository {repo_id}")
            
            # Fetch all
            result = subprocess.run(
                ["git", "-C", str(repo_path), "fetch", "--all", "--quiet"],
                capture_output=True,
                text=True,
                timeout=120,
            )
            
            if result.returncode != 0:
                raise RepoServiceError(f"Git fetch failed: {result.stderr}")
            
            # Checkout branch
            result = subprocess.run(
                ["git", "-C", str(repo_path), "checkout", branch, "--quiet"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            
            if result.returncode != 0:
                raise RepoServiceError(f"Git checkout failed: {result.stderr}")
            
            # Get current commit before reset
            old_commit = _get_commit_hash(repo_path)
            
            # Reset to origin
            result = subprocess.run(
                ["git", "-C", str(repo_path), "reset", "--hard", f"origin/{branch}", "--quiet"],
                capture_output=True,
                text=True,
                timeout=60,
            )
            
            if result.returncode != 0:
                raise RepoServiceError(f"Git reset failed: {result.stderr}")
            
            new_commit = _get_commit_hash(repo_path)
            was_updated = old_commit != new_commit
        
        commit_hash = _get_commit_hash(repo_path)
        logger.info(f"Repository {repo_id} at commit {commit_hash[:8]}")
        
        return commit_hash, was_updated
        
    except subprocess.TimeoutExpired:
        raise RepoServiceError("Git operation timed out")
    except Exception as e:
        if isinstance(e, RepoServiceError):
            raise
        raise RepoServiceError(f"Unexpected error: {str(e)}")


def _get_commit_hash(repo_path: Path) -> str:
    """Get the current commit hash of a repository."""
    result = subprocess.run(
        ["git", "-C", str(repo_path), "rev-parse", "HEAD"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        raise RepoServiceError("Failed to get commit hash")
    return result.stdout.strip()


def _sanitize_url(url: str) -> str:
    """Remove credentials from URL for logging."""
    if "@" in url:
        # URL contains credentials, sanitize
        proto_end = url.find("://") + 3
        at_pos = url.find("@")
        return url[:proto_end] + "***@" + url[at_pos + 1:]
    return url


def create_package_zip(
    repo_id: int,
    config_path: str,
    branch: str = "main",
    include_full_repo: bool = False
) -> Tuple[bytes, str, str]:
    """
    Create a ZIP package from a repository.
    
    Args:
        repo_id: Repository ID
        config_path: Path to the config within the repo (e.g., "nodes/server01.ps1")
        branch: Branch name
        include_full_repo: If True, include entire repo; if False, include only necessary files
    
    Returns:
        Tuple of (zip_bytes, commit_hash, package_hash)
    
    Raises:
        RepoServiceError: If the operation fails.
    """
    repo_path = get_repo_path(repo_id)
    
    if not repo_path.exists():
        raise RepoServiceError(f"Repository {repo_id} not found locally. Run sync first.")
    
    commit_hash = _get_commit_hash(repo_path)
    
    # Create ZIP in memory
    zip_buffer = tempfile.SpooledTemporaryFile(max_size=50 * 1024 * 1024)  # 50MB in memory
    
    try:
        with zipfile.ZipFile(zip_buffer, 'w', zipfile.ZIP_DEFLATED) as zf:
            if include_full_repo:
                # Include entire repo (excluding .git)
                _add_directory_to_zip(zf, repo_path, repo_path, exclude_git=True)
            else:
                # Smart packaging: include config file and related directories
                config_full_path = repo_path / config_path
                
                if not config_full_path.exists():
                    raise RepoServiceError(f"Config path not found: {config_path}")
                
                if config_full_path.is_file():
                    # Add the config file
                    arcname = config_path
                    zf.write(config_full_path, arcname)
                    
                    # If it's a .ps1, also include baselines and common directories
                    if config_path.endswith('.ps1'):
                        _add_related_directories(zf, repo_path, config_path)
                else:
                    # It's a directory (e.g., mof directory)
                    _add_directory_to_zip(zf, config_full_path, repo_path, exclude_git=True)
                    
                    # Also add baselines if they exist
                    _add_related_directories(zf, repo_path, config_path)
            
            # Add metadata file
            metadata = f"commit={commit_hash}\npackaged_at={datetime.utcnow().isoformat()}\nconfig_path={config_path}\n"
            zf.writestr("_opentune_meta.txt", metadata)
        
        # Read ZIP content
        zip_buffer.seek(0)
        zip_bytes = zip_buffer.read()
        
        # Calculate package hash
        package_hash = hashlib.sha256(zip_bytes).hexdigest()[:16]
        
        return zip_bytes, commit_hash, package_hash
        
    finally:
        zip_buffer.close()


def _add_directory_to_zip(
    zf: zipfile.ZipFile,
    directory: Path,
    base_path: Path,
    exclude_git: bool = True
):
    """Recursively add a directory to a ZIP file."""
    for item in directory.rglob("*"):
        if exclude_git and ".git" in item.parts:
            continue
        if item.is_file():
            arcname = str(item.relative_to(base_path))
            zf.write(item, arcname)


def _add_related_directories(zf: zipfile.ZipFile, repo_path: Path, config_path: str):
    """Add related directories (baselines, common, etc.) to the ZIP."""
    # Common directories that might be needed
    related_dirs = ["baselines", "common", "modules", "lib"]
    
    for dirname in related_dirs:
        dir_path = repo_path / dirname
        if dir_path.exists() and dir_path.is_dir():
            _add_directory_to_zip(zf, dir_path, repo_path, exclude_git=True)
    
    # Also include any .ps1 files in the same directory as the config
    config_dir = (repo_path / config_path).parent
    if config_dir.exists():
        for ps1_file in config_dir.glob("*.ps1"):
            arcname = str(ps1_file.relative_to(repo_path))
            if arcname not in [m.filename for m in zf.filelist]:
                zf.write(ps1_file, arcname)


def delete_repo(repo_id: int) -> bool:
    """
    Delete a local repository clone.
    
    Returns:
        True if deleted, False if didn't exist.
    """
    repo_path = get_repo_path(repo_id)
    
    if repo_path.exists():
        shutil.rmtree(repo_path)
        logger.info(f"Deleted local repository {repo_id}")
        return True
    
    return False


def get_repo_status(repo_id: int) -> Optional[dict]:
    """
    Get status information about a local repository.
    
    Returns:
        Dict with status info, or None if repo doesn't exist.
    """
    repo_path = get_repo_path(repo_id)
    
    if not repo_path.exists():
        return None
    
    try:
        commit = _get_commit_hash(repo_path)
        
        # Get last modified time
        git_dir = repo_path / ".git"
        mtime = datetime.fromtimestamp(git_dir.stat().st_mtime)
        
        # Get current branch
        result = subprocess.run(
            ["git", "-C", str(repo_path), "rev-parse", "--abbrev-ref", "HEAD"],
            capture_output=True,
            text=True,
        )
        branch = result.stdout.strip() if result.returncode == 0 else "unknown"
        
        return {
            "repo_id": repo_id,
            "commit": commit,
            "branch": branch,
            "last_updated": mtime.isoformat(),
            "path": str(repo_path),
        }
    except Exception as e:
        logger.error(f"Failed to get repo status: {e}")
        return None
