"""Fetch database credentials from AWS Secrets Manager with a small TTL cache.

Why fetch at runtime instead of injecting into env vars?
* RDS rotates the managed master secret automatically. A value copied into an
  environment variable at container start becomes stale after rotation; a value
  fetched (and re-fetched on auth failure) keeps working.
* The secret never appears in the task definition, `docker inspect`, the EC2
  user data or the process environment.
"""
import json
import threading
import time

from .config import settings

_lock = threading.Lock()
_cache: dict = {"value": None, "expires": 0.0}


def _fetch_from_secrets_manager() -> dict:
    import boto3  # imported lazily so local dev/tests don't need AWS

    client = boto3.client("secretsmanager", region_name=settings.aws_region)
    resp = client.get_secret_value(SecretId=settings.db_secret_arn)
    return json.loads(resp["SecretString"])


def get_db_credentials(force_refresh: bool = False) -> tuple[str, str]:
    """Return (username, password)."""
    if not settings.db_secret_arn:
        return settings.db_user, settings.db_password

    with _lock:
        now = time.time()
        if force_refresh or _cache["value"] is None or now >= _cache["expires"]:
            _cache["value"] = _fetch_from_secrets_manager()
            _cache["expires"] = now + settings.secret_cache_seconds
        secret = _cache["value"]
    return secret["username"], secret["password"]
