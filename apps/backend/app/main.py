"""R2 backend API (FastAPI).

All routes live under /api because the Application Load Balancer forwards
`/api/*` to this service and everything else to the Next.js frontend.
"""
import logging
from contextlib import asynccontextmanager

from fastapi import Depends, FastAPI, HTTPException
from pydantic import BaseModel, Field

from .config import settings
from .db import Repository, repository

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(name)s %(message)s")
log = logging.getLogger("r2app.backend")


def get_repo() -> Repository:
    return repository


@asynccontextmanager
async def lifespan(_: FastAPI):
    # Create the schema on startup. A real project would run Alembic migrations
    # as a separate pipeline step; this keeps the demo self-contained.
    try:
        repository.init_schema()
        log.info("Database schema ready")
    except Exception as exc:  # do not crash: /api/health must still answer
        log.warning("Could not initialise schema yet: %s", exc)
    yield


app = FastAPI(title="R2 Backend", version=settings.app_version, lifespan=lifespan,
              docs_url="/api/docs", openapi_url="/api/openapi.json")


class ItemIn(BaseModel):
    name: str = Field(min_length=1, max_length=200)


@app.get("/api/health")
def health():
    """Liveness probe used by the ALB target group.

    Deliberately does NOT touch the database: a DB blip must not make the load
    balancer kill every healthy application task at once.
    """
    return {"status": "ok", "version": settings.app_version}


@app.get("/api/ready")
def ready(repo: Repository = Depends(get_repo)):
    """Readiness / deep health check including the database."""
    try:
        repo.ping()
        db = "connected"
    except Exception as exc:
        log.error("DB check failed: %s", exc)
        raise HTTPException(status_code=503, detail="database unavailable")
    return {"status": "ready", "database": db}


@app.get("/api/info")
def info(repo: Repository = Depends(get_repo)):
    try:
        repo.ping()
        db = "connected"
    except Exception:
        db = "unavailable"
    return {
        "service": "backend",
        "environment": settings.app_env,
        "version": settings.app_version,
        "deployment_target": settings.deployment_target,
        "database": db,
    }


@app.get("/api/items")
def list_items(repo: Repository = Depends(get_repo)):
    return repo.list_items()


@app.post("/api/items", status_code=201)
def create_item(item: ItemIn, repo: Repository = Depends(get_repo)):
    return repo.create_item(item.name.strip())
