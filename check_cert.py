"""校验 Cloudflare 源站证书与私钥文件。

用法：
    python check_cert.py <证书路径> <私钥路径>

校验内容：
  1. 文件存在且非空
  2. PEM 能被正确解析（能发现粘贴时丢字符/断行的问题）
  3. 证书主题、签发者、有效期
  4. 证书与私钥是否配对（公钥指纹必须一致）

为什么需要它：往终端里粘贴长 base64 很容易丢字符，
而 openssl 只会回一句 "Could not read certificate"，不告诉你哪里坏了。
这里会把具体的坏行号指出来。
"""

import sys
import base64
from datetime import datetime, timezone

try:
    from cryptography import x509
    from cryptography.hazmat.primitives import serialization, hashes
    from cryptography.hazmat.primitives.asymmetric import rsa, ec
except ImportError:
    print("缺少 cryptography 库：pip install cryptography")
    sys.exit(2)


def bar(ok):
    return "[OK]  " if ok else "[FAIL]"


def check_pem_structure(path, label):
    """先按纯文本检查 PEM 结构，能定位到具体坏行。"""
    print(f"\n--- {label} 结构检查：{path} ---")
    try:
        raw = open(path, "rb").read()
    except FileNotFoundError:
        print(f"{bar(False)} 文件不存在")
        return None, None

    print(f"  大小: {len(raw)} 字节")
    if len(raw) == 0:
        print(f"{bar(False)} 文件为空")
        return None, None

    # 统一换行后按行处理
    text = raw.decode("utf-8", errors="replace").replace("\r\n", "\n").replace("\r", "\n")
    lines = text.split("\n")
    # 去掉尾部空行
    while lines and lines[-1].strip() == "":
        lines.pop()

    print(f"  行数: {len(lines)}")
    if not lines:
        print(f"{bar(False)} 没有有效内容")
        return None, None

    print(f"  首行: {lines[0]!r}")
    print(f"  末行: {lines[-1]!r}")

    ok = True
    if not lines[0].startswith("-----BEGIN "):
        print(f"{bar(False)} 首行不是 PEM 起始标记")
        ok = False
    if not lines[-1].startswith("-----END "):
        print(f"{bar(False)} 末行不是 PEM 结束标记（可能粘贴时被截断）")
        ok = False

    # base64 主体：定位非法字符与异常行长度
    body = lines[1:-1]
    bad_len = []
    bad_char = []
    for i, ln in enumerate(body, start=2):
        s = ln.strip()
        if s == "":
            continue
        if len(s) > 64:
            bad_len.append((i, len(s)))
        illegal = set(c for c in s if c not in "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/=")
        if illegal:
            bad_char.append((i, "".join(sorted(illegal))))

    if bad_len:
        print(f"{bar(False)} 以下行长度异常（正常 64 字符）：{bad_len[:5]}")
        ok = False
    if bad_char:
        print(f"{bar(False)} 以下行含非法字符：{bad_char[:5]}")
        ok = False

    joined = "".join(ln.strip() for ln in body)
    print(f"  base64 字符数: {len(joined)}")
    try:
        der = base64.b64decode(joined, validate=True)
        print(f"{bar(True)} base64 解码成功，DER 大小 {len(der)} 字节")
    except Exception as e:
        print(f"{bar(False)} base64 解码失败: {e}")
        print("        → 说明粘贴过程中丢了字符")
        return None, None

    if ok:
        print(f"{bar(True)} PEM 结构完整")
    return der, ok


def check_cert(path):
    print("=" * 62)
    print(f"证书文件: {path}")
    print("=" * 62)
    der, ok = check_pem_structure(path, "证书")
    if der is None:
        return None

    try:
        cert = x509.load_der_x509_certificate(der)
    except Exception as e:
        print(f"{bar(False)} 无法解析为 X.509 证书: {e}")
        return None

    print(f"\n{bar(True)} 证书解析成功")
    print(f"  主题:   {cert.subject.rfc4514_string()}")
    print(f"  签发者: {cert.issuer.rfc4514_string()}")
    print(f"  序列号: {cert.serial_number}")
    try:
        nb = cert.not_valid_before_utc
        na = cert.not_valid_after_utc
    except AttributeError:
        nb = cert.not_valid_before.replace(tzinfo=timezone.utc)
        na = cert.not_valid_after.replace(tzinfo=timezone.utc)
    now = datetime.now(timezone.utc)
    print(f"  有效期: {nb:%Y-%m-%d %H:%M} UTC → {na:%Y-%m-%d %H:%M} UTC")
    if nb <= now <= na:
        print(f"{bar(True)} 当前在有效期内")
    else:
        print(f"{bar(False)} 不在有效期内！")

    # SAN
    try:
        san = cert.extensions.get_extension_for_class(x509.SubjectAlternativeName)
        names = san.value.get_values_for_type(x509.DNSName)
        print(f"  SAN (DNS): {names}")
        if any(n == "api.hibiscus.wiki" or n == "*.hibiscus.wiki" for n in names):
            print(f"{bar(True)} 覆盖 api.hibiscus.wiki")
        else:
            print(f"{bar(False)} 未覆盖 api.hibiscus.wiki —— Cloudflare 回源会失败")
    except x509.ExtensionNotFound:
        print(f"  SAN: 无")

    pub = cert.public_key()
    if isinstance(pub, rsa.RSAPublicKey):
        print(f"  公钥算法: RSA {pub.key_size} 位  (Cloudflare 兼容性最好)")
    elif isinstance(pub, ec.EllipticCurvePublicKey):
        print(f"  公钥算法: ECDSA {pub.curve.name}  ⚠️ 建议改用 RSA")
    else:
        print(f"  公钥算法: {type(pub).__name__}")
    return cert


def check_key(path):
    print()
    print("=" * 62)
    print(f"私钥文件: {path}")
    print("=" * 62)
    der, ok = check_pem_structure(path, "私钥")
    if der is None:
        return None

    # 私钥的 PEM 主体是 PKCS#8，直接用 cryptography 的 PEM 加载更可靠
    try:
        raw = open(path, "rb").read()
        key = serialization.load_pem_private_key(raw, password=None)
    except Exception as e:
        print(f"{bar(False)} 无法加载私钥: {e}")
        return None

    print(f"\n{bar(True)} 私钥加载成功")
    if isinstance(key, rsa.RSAPrivateKey):
        print(f"  类型: RSA {key.key_size} 位")
    elif isinstance(key, ec.EllipticCurvePrivateKey):
        print(f"  类型: ECDSA {key.curve.name}")
    else:
        print(f"  类型: {type(key).__name__}")
    return key


def main():
    if len(sys.argv) < 3:
        print(__doc__)
        sys.exit(1)

    cert = check_cert(sys.argv[1])
    key = check_key(sys.argv[2])

    print()
    print("=" * 62)
    print("配对校验")
    print("=" * 62)
    if cert is None or key is None:
        print(f"{bar(False)} 有文件无法解析，无法配对")
        sys.exit(1)

    cert_pub = cert.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    key_pub = key.public_key().public_bytes(
        serialization.Encoding.DER,
        serialization.PublicFormat.SubjectPublicKeyInfo,
    )
    if cert_pub == key_pub:
        print(f"{bar(True)} 证书与私钥配对 —— 可以用于 Caddy")
    else:
        print(f"{bar(False)} 证书与私钥不配对！（两者不是同时生成的）")
        sys.exit(1)


if __name__ == "__main__":
    main()
