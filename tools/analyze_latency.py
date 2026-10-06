"""分析：TLS 握手开销 + Cloudflare 是否缓存了 API 响应。"""
import subprocess
import time

CURL = r"C:\WINDOWS\system32\curl.exe"
HOST = "api.hibiscus.wiki"
IP = "122.51.191.145"
PATH = "/api/v1/app/version"


def phases(url, extra=None, label=""):
    """用 curl 的 %{time_*} 拆解各阶段耗时。"""
    fmt = ("dns=%{time_namelookup} conn=%{time_connect} "
           "tls=%{time_appconnect} ttfb=%{time_starttransfer} "
           "total=%{time_total} code=%{http_code}")
    args = [CURL, "-s", "-o", "NUL", "-w", fmt, "--max-time", "30"]
    if extra:
        args += extra
    args.append(url)
    best = None
    for _ in range(3):
        out = subprocess.run(args, capture_output=True, timeout=45).stdout.decode().strip()
        try:
            vals = {}
            for kv in out.split():
                k, v = kv.split("=")
                vals[k] = v
            t = float(vals["total"])
            if best is None or t < best[0]:
                best = (t, vals)
        except Exception:
            pass
    if best:
        _, v = best
        print("  %-30s dns=%-7s conn=%-7s tls=%-7s ttfb=%-7s total=%-7s %s" % (
            label, v["dns"], v["conn"], v["tls"], v["ttfb"], v["total"], v["code"]))
        return v
    print("  %-30s 失败" % label)
    return None


print("=== 各阶段耗时拆解（取 3 次中最快的一次）===")
print("  dns=域名解析  conn=TCP连接  tls=TLS握手完成  ttfb=首字节  total=总耗时")
print()
phases("http://122.51.191.145:8080" + PATH, None, "明文 IP:8080")
phases("https://%s:8443%s" % (HOST, PATH),
       ["--resolve", "%s:8443:%s" % (HOST, IP)], "HTTPS 直连(灰云模拟)")
phases("https://%s:8443%s" % (HOST, PATH), None, "HTTPS 经 CF(橙云)")

print()
print("=== Cloudflare 是否缓存了 API 响应 ===")
out = subprocess.run([CURL, "-s", "-I", "--max-time", "30",
                      "https://%s:8443%s" % (HOST, PATH)],
                     capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
for line in out.split("\n"):
    l = line.strip()
    low = l.lower()
    if low.startswith(("http/", "cf-cache-status", "cache-control", "age:",
                       "cf-ray", "vary")):
        print("  %s" % l[:120])

print()
print("=== 第二次请求是否变快（判断是否缓存命中）===")
for i in range(3):
    out = subprocess.run([CURL, "-s", "-o", "NUL", "-w", "%{time_total}",
                          "--max-time", "30",
                          "https://%s:8443%s" % (HOST, PATH)],
                         capture_output=True, timeout=45).stdout.decode().strip()
    print("  第 %d 次经 CF: %s 秒" % (i + 1, out))
