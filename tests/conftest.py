"""Shared pytest fixtures for the Flask backend.

Sets high rate-limit ceilings and a fixed JWT secret via environment
variables *before* app.py is imported (its constants are read once, at
import time) so the suite can make many requests back-to-back without
tripping the same per-IP/per-account limits real traffic would hit.
Every test gets its own throwaway SQLite file — nothing here ever touches
a developer's real rasoicare.db.
"""
import os
import tempfile

os.environ.setdefault("JWT_SECRET", "test-secret-do-not-use-in-production")
os.environ.setdefault("RATE_LIMIT_GLOBAL_MAX_CALLS", "100000")
os.environ.setdefault("RATE_LIMIT_PUBLIC_MAX_CALLS", "100000")
os.environ.setdefault("RATE_LIMIT_AUTHENTICATED_MAX_CALLS", "100000")
os.environ.setdefault("RATE_LIMIT_AUTH_ACCOUNT_FREE_ATTEMPTS", "100000")
os.environ.setdefault("RATE_LIMIT_AUTH_IP_FREE_ATTEMPTS", "100000")

import pytest

import database
import app as app_module


@pytest.fixture()
def client(monkeypatch):
    """A Flask test client backed by a fresh, empty database for this
    one test — schema + catalog/staff seed data, nothing else."""
    fd, path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    monkeypatch.setattr(database, "DB_PATH", path)
    database.init_db()
    app_module.app.testing = True
    with app_module.app.test_client() as c:
        yield c
    os.unlink(path)


def register_and_login(client, email="alice@example.com", password="hunter22", name="Alice", phone="9876543210"):
    resp = client.post(
        "/api/auth/register",
        json={"email": email, "password": password, "name": name, "phone": phone},
    )
    assert resp.status_code == 201, resp.get_json()
    return resp.get_json()


def auth_headers(token):
    return {"Authorization": "Bearer " + token}


def add_technician(conn, tid="tech1", category="RasoiSpark", area="Test Area"):
    conn.execute(
        "INSERT INTO technicians (id, name, category, area, verified, online, rating, rating_count, jobs_completed) "
        "VALUES (?,?,?,?,1,1,4.5,10,10)",
        (tid, "Test Technician", category, area),
    )
    conn.commit()
