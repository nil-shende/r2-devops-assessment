"""Thin PostgreSQL data-access layer (psycopg 3)."""
from contextlib import contextmanager

import psycopg
from psycopg.rows import dict_row

from .config import settings
from .secret_store import get_db_credentials

SCHEMA_SQL = """
CREATE TABLE IF NOT EXISTS items (
    id          SERIAL PRIMARY KEY,
    name        VARCHAR(200) NOT NULL,
    created_at  TIMESTAMPTZ NOT NULL DEFAULT now()
);
"""


def _connect(force_refresh: bool = False) -> psycopg.Connection:
    user, password = get_db_credentials(force_refresh=force_refresh)
    return psycopg.connect(
        host=settings.db_host,
        port=settings.db_port,
        dbname=settings.db_name,
        user=user,
        password=password,
        sslmode=settings.db_sslmode,
        connect_timeout=5,
        row_factory=dict_row,
    )


@contextmanager
def get_connection():
    try:
        conn = _connect()
    except psycopg.OperationalError:
        # Most likely the password was rotated -> refresh the secret and retry once.
        conn = _connect(force_refresh=True)
    try:
        yield conn
        conn.commit()
    except Exception:
        conn.rollback()
        raise
    finally:
        conn.close()


class Repository:
    def init_schema(self) -> None:
        with get_connection() as conn:
            conn.execute(SCHEMA_SQL)

    def ping(self) -> bool:
        with get_connection() as conn:
            conn.execute("SELECT 1")
        return True

    def list_items(self) -> list[dict]:
        with get_connection() as conn:
            rows = conn.execute(
                "SELECT id, name, created_at FROM items ORDER BY id DESC LIMIT 100"
            ).fetchall()
        return [dict(r, created_at=r["created_at"].isoformat()) for r in rows]

    def create_item(self, name: str) -> dict:
        with get_connection() as conn:
            row = conn.execute(
                "INSERT INTO items (name) VALUES (%s) RETURNING id, name, created_at",
                (name,),
            ).fetchone()
        return dict(row, created_at=row["created_at"].isoformat())


repository = Repository()
