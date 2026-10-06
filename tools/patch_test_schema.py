"""同步测试用 schema（H2）：加 user 资料字段、message.media_url、chat_preference 表。

为什么用脚本而不是手改：PowerShell 的 here-string 会吃掉反引号/转义，
中文注释也容易被 GBK 控制台破坏；Python 按字节处理最稳。
"""

import re
import sys

PATH = r"C:\Users\沐瑾\Desktop\project\campus-run-backend\campus-run-server\src\test\resources\schema.sql"

src = open(PATH, "r", encoding="utf-8").read()
original = src
eol = "\r\n" if "\r\n" in src else "\n"
print(f"行尾: {'CRLF' if eol == chr(13)+chr(10) else 'LF'}")

# ── 1. user 表：在 role 之前插入 4 个字段 ─────────────────────────
user_block = re.search(r"CREATE TABLE user \((.*?)\n\s*\);", src, re.S)
if not user_block:
    print("FAIL: 找不到 CREATE TABLE user")
    sys.exit(1)

body = user_block.group(1)
if "gender_public" not in body:
    new_cols = [
        "      gender        TINYINT      DEFAULT NULL,",
        "      age           INT          DEFAULT NULL,",
        "      gender_public TINYINT      NOT NULL DEFAULT 0,",
        "      age_public    TINYINT      NOT NULL DEFAULT 0,",
    ]
    # 插到 role 行之前
    body_new = re.sub(r"(\n\s*role\s+TINYINT)",
                      "\n" + "\n".join(new_cols) + r"\1",
                      body, count=1)
    if body_new == body:
        print("FAIL: user 表里找不到 role 列")
        sys.exit(1)
    src = src.replace(body, body_new, 1)
    print("OK  user 表已加 gender/age/gender_public/age_public")
else:
    print("SKIP user 表已有字段")

# ── 2. message 表：content 可空 + 加 media_url ────────────────────
msg_block = re.search(r"CREATE TABLE message \((.*?)\n\s*\);", src, re.S)
if not msg_block:
    print("FAIL: 找不到 CREATE TABLE message")
    sys.exit(1)

mbody = msg_block.group(1)
mnew = mbody
if "media_url" not in mbody:
    mnew = re.sub(r"(\n\s*content\s+VARCHAR\(2000\)\s+NOT NULL,)",
                  r"\1".replace("\\1", "") + "",
                  mnew, count=1)
    # content 改为可空；并在 type 之后加 media_url
    mnew = mnew.replace("content     VARCHAR(2000) NOT NULL,",
                        "content     VARCHAR(2000),")
    mnew = re.sub(r"(type\s+TINYINT\s+NOT NULL DEFAULT 1,)",
                  r"\1\n      media_url   VARCHAR(255),",
                  mnew, count=1)
    if mnew == mbody:
        print("FAIL: message 表改动未生效")
        sys.exit(1)
    src = src.replace(mbody, mnew, 1)
    print("OK  message 表：content 可空 + 加 media_url")
else:
    print("SKIP message 表已有 media_url")

# ── 3. 追加 chat_preference 表 ────────────────────────────────────
if "chat_preference" not in src:
    chat_ddl = """
DROP TABLE IF EXISTS chat_preference;
CREATE TABLE chat_preference (
    id         BIGINT   NOT NULL AUTO_INCREMENT PRIMARY KEY,
    user_id    BIGINT   NOT NULL,
    friend_id  BIGINT   NOT NULL,
    muted      TINYINT  NOT NULL DEFAULT 0,
    created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
    CONSTRAINT uk_chat_pref_user_friend UNIQUE (user_id, friend_id)
);
CREATE INDEX idx_chat_pref_user_muted ON chat_preference (user_id, muted);
"""
    src = src.rstrip() + eol + chat_ddl
    print("OK  已追加 chat_preference 表")
else:
    print("SKIP chat_preference 已存在")

if src != original:
    open(PATH, "w", encoding="utf-8", newline="").write(src)
    print("已写回文件")
else:
    print("无改动")
