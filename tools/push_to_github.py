"""配置远程并推送项目到 GitHub（走本地代理）。"""
import os
import subprocess
import sys

PROJ = r"C:\Users\沐瑾\Desktop\project"
TOKEN = os.environ.get("GH_TOKEN", "")
REPO = "MuJin14/pace"
PROXY = "http://127.0.0.1:7897"


def run(args, check=True, env_extra=None, timeout=900):
    env = dict(os.environ)
    env["HTTPS_PROXY"] = PROXY
    env["HTTP_PROXY"] = PROXY
    if env_extra:
        env.update(env_extra)
    p = subprocess.run(args, cwd=PROJ, capture_output=True, timeout=timeout,
                       env=env)
    out = (p.stdout + p.stderr).decode("utf-8", "replace")
    if check and p.returncode != 0:
        print("  [失败 %d] %s" % (p.returncode, out.strip()[:600]))
    return p.returncode, out


if not TOKEN:
    print("  缺少 GH_TOKEN")
    sys.exit(1)

# ── 1) 配置远程（token 放在 URL 里，但不落盘到 .git/config 的明文？不行，会被写入）
# 所以改用 git 的 credential 方式：先把 remote 设成不带 token 的地址，
# 推送时通过 extraheader 传 Authorization。
print("=== 1) 配置 remote ===")
run(["git", "remote", "remove", "origin"], check=False)
code, out = run(["git", "remote", "add", "origin",
                 "https://github.com/%s.git" % REPO])
print("  remote origin -> https://github.com/%s.git" % REPO)

print()
print("=== 2) 检查待推送的提交 ===")
code, out = run(["git", "log", "--oneline", "-5"])
for line in out.strip().split("\n"):
    print("  %s" % line)

print()
print("=== 3) 当前分支名 ===")
code, branch = run(["git", "branch", "--show-current"])
branch = branch.strip() or "master"
print("  %s" % branch)

print()
print("=== 4) 推送（用 extraheader 传 token，不写进 .git/config）===")
import base64
auth = base64.b64encode(("x-access-token:" + TOKEN).encode()).decode()
code, out = run([
    "git", "-c", "http.extraheader=Authorization: Basic %s" % auth,
    "push", "-u", "origin", "%s:main" % branch,
], check=False, timeout=1800)
print(out.strip()[:1200])
print()
print("退出码: %d" % code)
