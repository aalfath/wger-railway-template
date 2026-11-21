#!/usr/bin/env python3
"""First-run setup and migrations for wger on Railway.

Holds a Postgres advisory lock while it runs, so two containers that start at the
same time (a redeploy overlapping a running deploy) never bootstrap or migrate the
database concurrently. Upstream's bootstrap loads an admin user with the well-known
password "adminadmin"; this replaces it with WGER_ADMIN_PASSWORD under the same lock.
"""
import os, subprocess, sys, time

import psycopg

LOCK_ID = 7_283_400_001


def run(*cmd):
    print("wger-railway: running", " ".join(cmd), flush=True)
    subprocess.run(cmd, check=True)


def main():
    url = os.environ["DATABASE_URL"]
    for attempt in range(60):
        try:
            conn = psycopg.connect(url, connect_timeout=5, autocommit=True)
            break
        except psycopg.OperationalError as exc:
            if attempt == 59:
                sys.exit(f"wger-railway: database not reachable: {exc}")
            print("wger-railway: waiting for the database", flush=True)
            time.sleep(3)

    with conn:
        print("wger-railway: waiting for the setup lock", flush=True)
        conn.execute("SELECT pg_advisory_lock(%s)", (LOCK_ID,))
        try:
            run("wger", "bootstrap", "--no-process-static")
            run("python3", "manage.py", "migrate", "--no-input")
            run("python3", "manage.py", "set-site-url")
            run("python3", "manage.py", "shell", "-c", ADMIN_FIX)
        finally:
            conn.execute("SELECT pg_advisory_unlock(%s)", (LOCK_ID,))


ADMIN_FIX = """
import os
from django.contrib.auth.models import User
u = User.objects.filter(username='admin').first()
if u and (u.check_password('adminadmin') or not u.has_usable_password()):
    u.set_password(os.environ['WGER_ADMIN_PASSWORD'])
    u.save()
    print('wger-railway: admin password set from WGER_ADMIN_PASSWORD')
"""

if __name__ == "__main__":
    main()
