"""Runtime configuration.

Non-secret settings come from environment variables that Infrastructure as Code
injects (ECS task definition `environment` block, or /etc/r2app/app.env on EC2).

Secrets (the database username/password) are NEVER passed as environment
variables. The app receives only the *ARN* of the AWS Secrets Manager secret and
fetches the value at runtime using its IAM role (see secrets.py).
"""
import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    app_env: str = os.getenv("APP_ENV", "local")
    app_version: str = os.getenv("APP_VERSION", "dev")
    deployment_target: str = os.getenv("DEPLOYMENT_TARGET", "local")
    aws_region: str = os.getenv("AWS_REGION", os.getenv("AWS_DEFAULT_REGION", "ap-south-1"))

    db_host: str = os.getenv("DB_HOST", "localhost")
    db_port: int = int(os.getenv("DB_PORT", "5432"))
    db_name: str = os.getenv("DB_NAME", "appdb")
    # Production: ARN of the RDS-managed secret in Secrets Manager.
    db_secret_arn: str = os.getenv("DB_SECRET_ARN", "")
    # Local development only (docker compose). Ignored when DB_SECRET_ARN is set.
    db_user: str = os.getenv("DB_USER", "postgres")
    db_password: str = os.getenv("DB_PASSWORD", "postgres")
    db_sslmode: str = os.getenv("DB_SSLMODE", "require")
    secret_cache_seconds: int = int(os.getenv("SECRET_CACHE_SECONDS", "300"))


settings = Settings()
