"""Provision (create or update) a DeerFlow user directly in the SQLite store.

Runs INSIDE the deer-flow container. Mirrors the exact password format the
Gateway writes: ``$dfv2$`` + bcrypt(b64(sha256(password))).

Usage (inside container):
    python3 /tmp/provision.py <email> <password> [role]
"""
import base64
import hashlib
import sqlite3
import sys
import uuid
from datetime import datetime, timezone

import bcrypt

DB = "/app/backend/.deer-flow/data/deerflow.db"


def hash_password_v2(password: str) -> str:
    pre = base64.b64encode(hashlib.sha256(password.encode("utf-8")).digest())
    raw = bcrypt.hashpw(pre, bcrypt.gensalt()).decode("utf-8")
    return "$dfv2$" + raw


def main() -> int:
    if len(sys.argv) < 3:
        print("usage: provision.py <email> <password> [role]", file=sys.stderr)
        return 2
    email = sys.argv[1].strip().lower()
    password = sys.argv[2]
    role = sys.argv[3] if len(sys.argv) > 3 else "user"
    if role not in ("admin", "user"):
        print("role must be admin or user", file=sys.stderr)
        return 2

    con = sqlite3.connect(DB)
    con.execute("PRAGMA foreign_keys=ON")
    cur = con.execute("SELECT id FROM users WHERE lower(email)=?", (email,))
    row = cur.fetchone()

    if row:
        con.execute(
            "UPDATE users SET password_hash=?, system_role=?, needs_setup=0, "
            "token_version=token_version+1 WHERE id=?",
            (hash_password_v2(password), role, row[0]),
        )
        print("UPDATED existing user:", email, "role=", role)
    else:
        con.execute(
            "INSERT INTO users (id, email, password_hash, system_role, created_at, "
            "oauth_provider, oauth_id, needs_setup, token_version) "
            "VALUES (?,?,?,?,?,NULL,NULL,0,0)",
            (
                str(uuid.uuid4()),
                email,
                hash_password_v2(password),
                role,
                datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%S.%f"),
            ),
        )
        print("CREATED user:", email, "role=", role)

    con.commit()
    print("current users:")
    for r in con.execute("SELECT email, system_role FROM users ORDER BY created_at"):
        print("   ", r)
    con.close()
    return 0


if __name__ == "__main__":
    sys.exit(main())
