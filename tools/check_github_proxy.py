"""检查代理环境下的 GitHub 可达性。"""
import os
import socket
import subprocess
import time

CURL = r"C:\WINDOWS\system32\curl.exe"

print("=== 1) 本机代理相关环境变量 ===")
found = False
for k, v in sorted(os.environ.items()):
    if any(t in k.lower() for t in ("proxy", "http_proxy", "https_proxy", "all_proxy")):
        print("  %s = %s" % (k, v))
        found = True
if not found:
    print("  无代理环境变量")

print()
print("=== 2) 系统 WinINET 代理设置 ===")
out = subprocess.run(
    ["reg", "query",
     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
     "/v", "ProxyEnable"], capture_output=True, timeout=30).stdout.decode("gbk", "replace")
print("  %s" % out.strip().replace("\n", "\n  "))
out = subprocess.run(
    ["reg", "query",
     r"HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings",
     "/v", "ProxyServer"], capture_output=True, timeout=30).stdout.decode("gbk", "replace")
print("  %s" % out.strip().replace("\n", "\n  "))

print()
print("=== 3) 常见代理端口是否在监听 ===")
for port in (7890, 7897, 10809, 10808, 1080, 8080, 2080, 33210):
    s = socket.socket()
    s.settimeout(0.6)
    try:
        s.connect(("127.0.0.1", port))
        print("  %-6s OPEN" % port)
    except Exception:
        pass
    finally:
        s.close()

print()
print("=== 4) 直连 GitHub（不走代理）===")


def probe(label, url, extra=None):
    args = [CURL, "-s", "-o", "NUL", "-w", "%{http_code} %{time_total}",
            "--max-time", "20"]
    if extra:
        args += extra
    args.append(url)
    t0 = time.time()
    out = subprocess.run(args, capture_output=True, timeout=45).stdout.decode().strip()
    print("  %-28s %s  (%.1fs)" % (label, out, time.time() - t0))


probe("github.com", "https://github.com")
probe("api.github.com", "https://api.github.com")
probe("objects.githubusercontent", "https://objects.githubusercontent.com")

print()
print("=== 5) 走常见代理端口试 GitHub ===")
for port in (7890, 7897, 10809, 1080, 2080):
    probe("github.com via :%d" % port, "https://github.com",
          ["-x", "http://127.0.0.1:%d" % port])
