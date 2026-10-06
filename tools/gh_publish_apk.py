"""在指定 GitHub 仓库创建 Release 并上传 APK。

用法：
    set GH_TOKEN=github_pat_...
    python gh_publish_apk.py MuJin14/pace v2.0.0 C:\\path\\campus-run.apk

⚠️ token 只从环境变量读，不落盘、不打印。
"""
import json
import os
import subprocess
import sys

CURL = r"C:\WINDOWS\system32\curl.exe"
API = "https://api.github.com"


def curl(args, timeout=1800):
    return subprocess.run([CURL] + args, capture_output=True,
                          timeout=timeout).stdout.decode("utf-8", "replace")


def api(method, path, token, body=None, timeout=120):
    args = ["-s", "-w", "\n%{http_code}", "--max-time", str(timeout),
            "-X", method,
            "-H", "Authorization: Bearer " + token,
            "-H", "Accept: application/vnd.github+json",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "-H", "User-Agent: campus-run-release"]
    if body is not None:
        args += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    args.append(API + path)
    out = curl(args)
    *payload, code = out.rsplit("\n", 1)
    text = "\n".join(payload)
    try:
        return int(code), (json.loads(text) if text.strip() else None)
    except Exception:
        return int(code), text


def upload(upload_url, token, apk, name):
    """上传资产。用 --data-binary 直接送文件，避免读进内存。"""
    url = "%s?name=%s" % (upload_url, name)
    args = ["-s", "-w", "\n%{http_code}", "--max-time", "3600",
            "-X", "POST",
            "-H", "Authorization: Bearer " + token,
            "-H", "Content-Type: application/vnd.android.package-archive",
            "-H", "X-GitHub-Api-Version: 2022-11-28",
            "-H", "User-Agent: campus-run-release",
            "--data-binary", "@" + apk,
            url]
    out = curl(args, timeout=3600)
    *payload, code = out.rsplit("\n", 1)
    text = "\n".join(payload)
    try:
        return int(code), json.loads(text)
    except Exception:
        return int(code), text


def main():
    if len(sys.argv) < 4:
        print("用法: gh_publish_apk.py <owner/repo> <tag> <apk 路径>")
        return 1
    repo, tag, apk = sys.argv[1], sys.argv[2], sys.argv[3]
    token = os.environ.get("GH_TOKEN", "")
    if not token:
        print("  缺少 GH_TOKEN")
        return 1
    if not os.path.exists(apk):
        print("  APK 不存在: %s" % apk)
        return 1

    size = os.path.getsize(apk)
    print("  仓库   : %s" % repo)
    print("  标签   : %s" % tag)
    print("  文件   : %.1f MB" % (size / 1048576))

    # ── 1) 建 Release（已存在则复用）──
    code, rel = api("POST", "/repos/%s/releases" % repo, token, {
        "tag_name": tag,
        "name": "校园跑 %s" % tag,
        "body": "校园跑 App 安装包（Android）。\n\n"
                "下载下方 `campus-run.apk` 直接安装即可。",
        "draft": False,
        "prerelease": False,
    })
    if code == 422:
        print("  该标签的 Release 已存在，改为复用")
        code, rel = api("GET", "/repos/%s/releases/tags/%s" % (repo, tag), token)
    if code not in (200, 201):
        print("  创建 Release 失败 (%s): %s" % (code, str(rel)[:300]))
        return 1
    print("  Release: %s" % rel["html_url"])

    # ── 2) 上传资产（同名先删，避免 422）──
    asset_name = "campus-run.apk"
    for a in rel.get("assets", []):
        if a["name"] == asset_name:
            print("  已存在同名资产，先删除 id=%s" % a["id"])
            api("DELETE", "/repos/%s/releases/assets/%s" % (repo, a["id"]), token)

    upload_url = rel["upload_url"].replace("{?name,label}", "")
    print("  正在上传（54MB，可能需要一两分钟）…")
    code, asset = upload(upload_url, token, apk, asset_name)
    if code not in (200, 201):
        print("  上传失败 (%s): %s" % (code, str(asset)[:400]))
        return 1

    print("  上传成功")
    print("  资产大小: %s 字节" % asset.get("size"))
    print("  下载地址: %s" % asset.get("browser_download_url"))
    return 0


if __name__ == "__main__":
    sys.exit(main())
