"""修复测试 schema 的 message.user 两处损坏（一次性修复脚本）。

问题：上一步用 PowerShell 做多行替换时换行处理不可靠，
导致 message 表丢了 content 列，且新增字段缩进不一致。
"""

import re
import sys

PATH = r"C:\Users\沐瑾\Desktop\project\campus-run-backend\campus-run-server\src\test\resources\schema.sql"
src = open(PATH, "r", encoding="utf-8").read()
original = src

# ── 1. message 表：补回 content，并修正 media_url 缩进 ────────────
m = re.search(r"(CREATE TABLE message \()(.*?)(\n\s*\);)", src, re.S)
if not m:
    print("FAIL 找不到 message 表")
    sys.exit(1)

head, body, tail = m.group(1), m.group(2), m.group(3)

if "content" not in body:
    # 在 receiver_id 行之后插入 content
    body = re.sub(
        r"(\n\s*receiver_id\s+BIGINT\s+NOT NULL,)",
        r"\1\n      content     VARCHAR(2000),",
        body, count=1,
    )
    print("OK  已补回 message.content")
else:
    print("SKIP message.content 已存在")

# 统一 media_url 缩进为 6 空格
body = re.sub(r"\n\s*media_url\s+VARCHAR\(255\),",
              "\n      media_url   VARCHAR(255),", body, count=1)

src = src[:m.start()] + head + body + tail + src[m.end():]

# ── 2. user 表：统一新增字段缩进 ─────────────────────────────────
u = re.search(r"(CREATE TABLE user \()(.*?)(\n\s*\);)", src, re.S)
if u:
    uhead, ubody, utail = u.group(1), u.group(2), u.group(3)
    before = ubody
    for col in ["gender        TINYINT      DEFAULT NULL,",
                "age           INT          DEFAULT NULL,",
                "gender_public TINYINT      NOT NULL DEFAULT 0,",
                "age_public    TINYINT      NOT NULL DEFAULT 0,"]:
        ubody = re.sub(r"\n\s*" + re.escape(col), "\n      " + col, ubody, count=1)
    if ubody != before:
        src = src[:u.start()] + uhead + ubody + utail + src[u.end():]
        print("OK  已修正 user 表缩进")

if src != original:
    open(PATH, "w", encoding="utf-8", newline="").write(src)
    print("已写回")
else:
    print("无改动")

# ── 3. 验证 ──────────────────────────────────────────────────────
check = open(PATH, "r", encoding="utf-8").read()
mb = re.search(r"CREATE TABLE message \((.*?)\n\s*\);", check, re.S).group(1)
ub = re.search(r"CREATE TABLE user \((.*?)\n\s*\);", check, re.S).group(1)
print("\n=== message 列 ===")
for line in mb.strip().split("\n"):
    print("  " + line.strip())
print("\n=== user 列 ===")
for line in ub.strip().split("\n"):
    print("  " + line.strip())
print("\n校验: message.content 存在 =", "content" in mb)
print("校验: message.media_url 存在 =", "media_url" in mb)
print("校验: user.gender_public 存在 =", "gender_public" in ub)
print("校验: chat_preference 存在 =", "chat_preference" in check)
