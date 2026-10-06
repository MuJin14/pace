"""Grant admin role to the three owner accounts and verify the security boundary.

Run: python tools/grant_admin.py <db_password>
"""
import io
import json
import subprocess
import sys
import urllib.error
import urllib.request

BASE = "http://122.51.191.145:8080"
SERVER = "ubuntu@122.51.191.145"

OWNER_PHONES = ["13800138000", "17530554523", "19561723890"]


def api(path, method="GET", token=None, body=None):
    req = urllib.request.Request(BASE + path, method=method)
    if token:
        req.add_header("Authorization", "Bearer " + token)
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        req.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(req, data, timeout=30) as r:
            return r.status, json.loads(r.read().decode())
    except urllib.error.HTTPError as e:
        try:
            return e.code, json.loads(e.read().decode())
        except Exception:
            return e.code, None


def login(phone, password):
    st, js = api("/api/v1/auth/login", "POST", body={"phone": phone, "password": password})
    if st != 200 or not js or js.get("code") != 0:
        return None
    return js["data"]


def run_remote(sql, db_password):
    """Run one SQL statement inside the MySQL container over SSH."""
    inner = (
        'D="docker"; docker ps >/dev/null 2>&1 || D="sudo docker"; '
        '$D exec campus-run-mysql mysql -uroot -p"%s" --default-character-set=utf8mb4 '
        "campus_run -e \"%s\" 2>&1 | grep -v 'Using a password'"
    ) % (db_password, sql)
    out = subprocess.run(
        ["ssh", "-o", "StrictHostKeyChecking=no", SERVER, inner],
        capture_output=True, text=True, timeout=120,
    )
    return (out.stdout or "") + (out.stderr or "")


def main():
    if len(sys.argv) < 2:
        print("usage: grant_admin.py <db_password>")
        return 1
    dbp = sys.argv[1]

    phones = ",".join("'%s'" % p for p in OWNER_PHONES)
    print("=== granting admin to %s ===" % OWNER_PHONES)
    print(run_remote(
        "UPDATE user SET role = 1 WHERE phone IN (%s); "
        "SELECT id, nickname, phone, role FROM user ORDER BY id;" % phones, dbp))

    print("=== verifying via API ===")
    for p in OWNER_PHONES:
        session = login(p, "secret123")
        if not session:
            print("  %s  -> login FAILED (password differs?)" % p)
            continue
        st, js = api("/api/v1/user/me", token=session["token"])
        role = (js or {}).get("data", {}).get("role")
        st2, js2 = api("/api/v1/admin/users?size=1", token=session["token"])
        print("  %s  role=%s  admin-api=%s" % (p, role, st2))

    print()
    print("=== security boundary: non-admin must be refused ===")
    other = login("13800138001", "secret123")
    if other:
        st, js = api("/api/v1/admin/users", token=other["token"])
        print("  TesterB (role=0) -> HTTP %s (expect 403)" % st)
        st, js = api("/api/v1/admin/users", token=other["token"])
        print("    body: %s" % js)
    st, js = api("/api/v1/admin/users")
    print("  no token -> HTTP %s (expect 401)" % st)
    return 0


if __name__ == "__main__":
    sys.exit(main())
