"""诊断：应用内更新下载的 APK 为何装不上。

排查顺序（按发生概率）：
  1. 安装包签名与已装版本不一致 → 系统直接拒绝覆盖安装
  2. 下载的包不完整/损坏 → 解析失败
  3. 安装器根本没被唤起（权限/Intent 问题）
  4. 包本身有问题（版本号、minSdk 等）
"""
import hashlib
import json
import os
import subprocess
import zipfile

ADB = r"C:\dev\Android\Sdk\platform-tools\adb.exe"
CURL = r"C:\WINDOWS\system32\curl.exe"
LOCAL_APK = r"C:\Users\沐瑾\Desktop\campus-run.apk"


def sh(*args, timeout=120):
    return subprocess.run([ADB] + list(args), capture_output=True,
                          timeout=timeout).stdout.decode("utf-8", "replace")


def sh_su(*args):
    """通过 run-as / su 读应用私有目录；失败返回 None。"""
    return sh("shell", *args)


print("=== 1) App 私有目录里的下载包 ===")
pkg = "com.example.campus_run_app"
# release 包 run-as 通常不可用，先试
out = sh_su("run-as", pkg, "ls", "-la", "files/")
if "Permission" in out or "not debuggable" in out or not out.strip():
    print("  run-as 不可用（release 包正常）")
    out2 = sh_su("ls", "-la", "/data/data/%s/files/" % pkg)
    print("  直接 ls: %s" % out2.strip()[:200] or "  无法读取（需 root）")
else:
    print(out)

print()
print("=== 2) 公开目录里有没有下载的包 ===")
for p in ("/sdcard/Download", "/sdcard/Android/data/%s/files" % pkg,
          "/storage/emulated/0/Download"):
    out = sh_su("ls", "-la", p)
    lines = [l for l in out.split("\n") if "apk" in l.lower()]
    if lines:
        print("  %s:" % p)
        for l in lines:
            print("    %s" % l.strip())
    else:
        print("  %s: 无 apk" % p)

print()
print("=== 3) 已安装版本的签名 ===")
out = sh("shell", "dumpsys", "package", pkg)
for line in out.split("\n"):
    if any(k in line for k in ("versionName", "versionCode", "signatures",
                               "signature", "installerPackageName",
                               "firstInstallTime", "lastUpdateTime")):
        print("  %s" % line.strip()[:150])

print()
print("=== 4) 桌面 APK 的签名与指纹 ===")
aapt2 = r"C:\Android\sdk\build-tools\36.1.0\aapt2.exe"
out = subprocess.run([aapt2, "dump", "badging", LOCAL_APK],
                     capture_output=True, timeout=120).stdout.decode("utf-8", "replace")
for line in out.split("\n"):
    if line.startswith("package:") or "sdkVersion" in line:
        print("  %s" % line.strip()[:150])

# 从 APK 里取签名证书指纹
print()
print("=== 5) APK 签名证书指纹（与设备上的对比）===")
try:
    out = subprocess.run(
        ["C:\\Program Files\\Git\\usr\\bin\\openssl.exe", "version"],
        capture_output=True, timeout=30)
except Exception:
    pass
# 用 Python 解析 META-INF 下的证书
z = zipfile.ZipFile(LOCAL_APK)
sigs = [n for n in z.namelist()
        if n.upper().startswith("META-INF/") and n.upper().endswith((".RSA", ".DSA", ".EC"))]
print("  签名文件: %s" % (sigs or "无（可能只有 v2/v3 签名）"))
for s in sigs:
    data = z.read(s)
    print("  %s: %d 字节  sha256=%s" % (
        s, len(data), hashlib.sha256(data).hexdigest()[:32]))

print()
print("=== 6) 本地 APK 完整性 ===")
h = hashlib.sha256(open(LOCAL_APK, "rb").read()).hexdigest()
print("  本地桌面 APK  sha256 = %s" % h)
print("  大小 = %d 字节" % os.path.getsize(LOCAL_APK))

# 服务器上的
out = subprocess.run([CURL, "-s", "--max-time", "30",
                      "https://api.hibiscus.wiki:8443/api/v1/app/version"],
                     capture_output=True, timeout=60).stdout.decode("utf-8", "replace")
try:
    d = json.loads(out)["data"]
    print("  服务端声明     sha256 = %s" % d.get("apkSha256"))
    print("  服务端声明     大小   = %s" % d.get("apkSizeBytes"))
    print("  一致: %s" % ("是" if h == d.get("apkSha256") else
                        "否 ← 服务端的包与桌面这份不同"))
except Exception as e:
    print("  拉版本信息失败: %s" % e)

print()
print("=== 7) 最近的安装器相关日志 ===")
out = sh("logcat", "-d", "-t", "400")
keys = ("PackageInstaller", "PackageManager", "INSTALL_FAILED", "install",
        "signatures do not match", "Verification", "ParseError", "package:")
seen = []
for line in out.split("\n"):
    if any(k.lower() in line.lower() for k in keys):
        seen.append(line.strip())
for l in seen[-25:]:
    print("  %s" % l[:170])
if not seen:
    print("  无相关日志")
