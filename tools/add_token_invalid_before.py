"""给 user 表加 token_invalid_before（改密后使旧 refresh token 失效）。"""

import re

BASE = r"C:\Users\沐瑾\Desktop\project\campus-run-backend"

# ── 1. 测试 schema（H2）──────────────────────────────────────────
TEST = BASE + r"\campus-run-server\src\test\resources\schema.sql"
src = open(TEST, "r", encoding="utf-8").read()
if "token_invalid_before" not in src:
    m = re.search(r"(CREATE TABLE user \()(.*?)(\n\s*\);)", src, re.S)
    head, body, tail = m.group(1), m.group(2), m.group(3)
    body = re.sub(r"(\n\s*age_public\s+TINYINT\s+NOT NULL DEFAULT 0,)",
                  r"\1\n      token_invalid_before TIMESTAMP  DEFAULT NULL,",
                  body, count=1)
    src = src[:m.start()] + head + body + tail + src[m.end():]
    open(TEST, "w", encoding="utf-8", newline="").write(src)
    print("OK  测试 schema 已加 token_invalid_before")
else:
    print("SKIP 测试 schema 已有")

# ── 2. docs/schema.sql ──────────────────────────────────────────
DOCS = BASE + r"\docs\schema.sql"
src = open(DOCS, "r", encoding="utf-8").read()
if "token_invalid_before" not in src:
    m = re.search(r"(CREATE TABLE IF NOT EXISTS `user` \()(.*?)(\n\s*\);)", src, re.S)
    head, body, tail = m.group(1), m.group(2), m.group(3)
    body = re.sub(r"(\n\s*`age_public`\s+TINYINT\s+NOT NULL DEFAULT 0[^\n]*)",
                  r"\1\n    `token_invalid_before` DATETIME DEFAULT NULL"
                  r" COMMENT '令牌失效时间：改密后写入，早于此时间签发的 refresh token 一律拒绝',",
                  body, count=1)
    src = src[:m.start()] + head + body + tail + src[m.end():]
    open(DOCS, "w", encoding="utf-8", newline="").write(src)
    print("OK  docs/schema.sql 已加 token_invalid_before")
else:
    print("SKIP docs/schema.sql 已有")

# ── 3. 迁移脚本追加一条 ─────────────────────────────────────────
MIG = BASE + r"\docs\migrations\002_profile_privacy_and_media.sql"
src = open(MIG, "r", encoding="utf-8").read()
if "token_invalid_before" not in src:
    anchor = "-- ── 2. message 表：富媒体"
    block = """-- 改密后使旧 refresh token 失效：签发时间早于该值的 refresh token 一律拒绝。
-- 不加这个的话，改密只能拦住"用新密码登录"，而小偷手里 30 天有效的
-- refresh token 仍然能换到新的 access token —— 等于没改。
SET @exists := (SELECT COUNT(*) FROM information_schema.COLUMNS
                WHERE TABLE_SCHEMA = @db AND TABLE_NAME = 'user' AND COLUMN_NAME = 'token_invalid_before');
SET @sql := IF(@exists = 0,
    'ALTER TABLE `user` ADD COLUMN `token_invalid_before` DATETIME DEFAULT NULL',
    'SELECT 1');
PREPARE s FROM @sql; EXECUTE s; DEALLOCATE PREPARE s;

"""
    src = src.replace(anchor, block + anchor, 1)
    open(MIG, "w", encoding="utf-8", newline="").write(src)
    print("OK  迁移脚本已追加 token_invalid_before")
else:
    print("SKIP 迁移脚本已有")

# ── 验证 ────────────────────────────────────────────────────────
print("\n=== 验证 ===")
for name, path in [("test", TEST), ("docs", DOCS), ("migration", MIG)]:
    t = open(path, "r", encoding="utf-8").read()
    print(f"  {name}: token_invalid_before = {'token_invalid_before' in t}")
