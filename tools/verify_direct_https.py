"""正确验证：App 若直连源站（绕过 Cloudflare），速度与证书如何。"""
import json
import subprocess
import time

CURL = r"C:\WINDOWS\system32\curl.exe"


def run(label, url, extra=None, times=4):
    ts, codes, body = [], [], ""
    for _ in range(times):
        args = [CURL, "-s", "-o", "-", "-w", "\n%{http_code} %{time_total}",
                "--max-time", "30"]
        if extra:
            args += extra
        args.append(url)
        out = subprocess.run(args, capture_output=True, timeout=45).stdout.decode(
            "utf-8", "replace")
        *b, meta = out.rsplit("\n", 1)
        try:
            c, t = meta.split()
            codes.append(c)
            ts.append(float(t))
            if not body:
                body = "\n".join(b)
        except Exception:
            pass
    if ts:
        ok = codes[0] == "200"
        print("  %-34s HTTP %-4s 平均 %.3f 秒  %s" % (
            label, codes[0], sum(ts) / len(ts),
            "OK" if ok else "失败"))
        return body if ok else ""
    print("  %-34s 全部失败" % label)
    return ""


HOST = "api.hibiscus.wiki"
IP = "122.51.191.145"

print("=== 三条线路对比（各 4 次）===")
b1 = run("明文 IP:8080（现状）",
         "http://122.51.191.145:8080/api/v1/app/version")
b2 = run("HTTPS 经 Cloudflare（橙云）",
         "https://%s:8443/api/v1/app/version" % HOST)
b3 = run("HTTPS 直连源站（模拟灰云）",
         "https://%s:8443/api/v1/app/version" % HOST,
         ["--resolve", "%s:8443:%s" % (HOST, IP)])

print()
print("=== 直连返回的内容是否与明文一致 ===")
try:
    d1 = json.loads(b1)["data"]
    d3 = json.loads(b3)["data"]
    print("  明文 latest=%s  apkReady=%s" % (d1.get("latest"), d1.get("apkReady")))
    print("  直连 latest=%s  apkReady=%s" % (d3.get("latest"), d3.get("apkReady")))
    print("  一致: %s" % ("是" if d1.get("latest") == d3.get("latest") else "否"))
except Exception as e:
    print("  解析失败: %s" % e)
    print("  直连原始响应: %s" % b3[:200])

print()
print("=== 登录接口（加密通道）===")
import random
ph = "138" + "".join(random.choice("0123456789") for _ in range(8))
out = subprocess.run([CURL, "-s", "-w", "\n%{http_code}", "--max-time", "30",
                      "-X", "POST", "-H", "Content-Type: application/json",
                      "-d", json.dumps({"phone": ph, "password": "wrong123"}),
                      "--resolve", "%s:8443:%s" % (HOST, IP),
                      "https://%s:8443/api/v1/auth/login" % HOST],
                     capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
*body, code = out.rsplit("\n", 1)
print("  HTTP %s  %s" % (code, "\n".join(body)[:120]))
