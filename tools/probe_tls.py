import socket
import ssl
import time


def probe(host, port, label, sni=None):
    """测 TLS 握手：能否连通 + 证书信息。"""
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = False
    ctx.verify_mode = ssl.CERT_NONE
    t0 = time.time()
    try:
        with socket.create_connection((host, port), timeout=8) as raw:
            with ctx.wrap_socket(raw, server_hostname=sni or host) as ss:
                cert = ss.getpeercert()
                tls = ss.version()
        hs = time.time() - t0
        subj = (cert or {}).get("subject", "?")
        print("  %-32s TLS %-9s handshake %.2fs" % (label, tls, hs))
        return True
    except Exception as e:
        print("  %-32s FAILED: %s" % (label, type(e).__name__))
        return False


def probe_verified(host, port, label):
    """用系统信任链验证（真实客户端行为）。"""
    try:
        ctx = ssl.create_default_context()
        with socket.create_connection((host, port), timeout=8) as raw:
            with ctx.wrap_socket(raw, server_hostname=host) as ss:
                print("  %-32s TRUSTED OK (%s)" % (label, ss.version()))
                return True
    except Exception as e:
        print("  %-32s NOT TRUSTED: %s" % (label, type(e).__name__))
        return False


print("=== 1) TLS reachability on existing endpoints ===")
probe("hibiscus.wiki", 443, "hibiscus.wiki:443")
probe("dl.hibiscus.wiki", 443, "dl.hibiscus.wiki:443")
probe("dl.hibiscus.wiki", 8443, "dl.hibiscus.wiki:8443")
probe("api.hibiscus.wiki", 443, "api.hibiscus.wiki:443")
probe("api.hibiscus.wiki", 8443, "api.hibiscus.wiki:8443")
probe("122.51.191.145", 8080, "122.51.191.145:8080 (plain)")
probe("122.51.191.145", 443, "122.51.191.145:443")

print()
print("=== 2) System-trust verification (what a real client does) ===")
probe_verified("hibiscus.wiki", 443, "hibiscus.wiki:443")
probe_verified("dl.hibiscus.wiki", 8443, "dl.hibiscus.wiki:8443")
probe_verified("api.hibiscus.wiki", 8443, "api.hibiscus.wiki:8443")
