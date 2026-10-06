"""把 api / dl 的 DNS 记录从橙云（CF 代理）改为灰云（仅 DNS，直连源站）。"""
import json
import os
import subprocess
import sys

CURL = r"C:\WINDOWS\system32\curl.exe"
TOKEN = os.environ.get("CF_TOKEN", "")
ZONE = "fc2dfd657f783ded0c38dd9285dbc829"
API = "https://api.cloudflare.com/client/v4"


def cf(method, path, body=None):
    args = [CURL, "-s", "-w", "\n%{http_code}", "--max-time", "40",
            "-X", method,
            "-H", "Authorization: Bearer " + TOKEN,
            "-H", "Content-Type: application/json"]
    if body is not None:
        args += ["-d", json.dumps(body)]
    args.append(API + path)
    out = subprocess.run(args, capture_output=True, timeout=90).stdout.decode(
        "utf-8", "replace")
    *payload, code = out.rsplit("\n", 1)
    try:
        return int(code), json.loads("\n".join(payload) or "null")
    except Exception:
        return int(code), "\n".join(payload)[:300]


TARGETS = {
    "api.hibiscus.wiki": "3f5fbad4770635d20b6248fcf21580aa",
    "dl.hibiscus.wiki": "fc4dbb6ea30479b91bcf4b182ea16f83",
}

dry = "--apply" not in sys.argv
print("模式: %s" % ("试运行（不改动）" if dry else "实际执行"))

for name, rid in TARGETS.items():
    code, r = cf("GET", "/zones/%s/dns_records/%s" % (ZONE, rid))
    if code != 200:
        print("  %-22s 读取失败 %s" % (name, code))
        continue
    rec = r["result"]
    print("  %-22s 当前 proxied=%s  content=%s" % (
        name, rec.get("proxied"), rec.get("content")))
    if dry:
        continue
    if rec.get("proxied") is False:
        print("  %-22s 已是灰云，跳过" % name)
        continue
    code, r = cf("PATCH", "/zones/%s/dns_records/%s" % (ZONE, rid),
                 {"proxied": False})
    ok = code == 200 and (r or {}).get("success")
    print("  %-22s 改为灰云: %s%s" % (
        name, "成功" if ok else "失败 " + str(code),
        "" if ok else " " + json.dumps(r, ensure_ascii=False)[:160]))

if not dry:
    print()
    print("=== 确认结果 ===")
    for name, rid in TARGETS.items():
        code, r = cf("GET", "/zones/%s/dns_records/%s" % (ZONE, rid))
        if code == 200:
            rec = r["result"]
            print("  %-22s proxied=%s" % (name, rec.get("proxied")))
