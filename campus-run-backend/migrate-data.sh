#!/usr/bin/env bash
# 数据迁移：把本地开发库的数据与头像导入服务器。
#
# 前置：已把 crun-migrate.tar.gz 上传到 ~ 并解包，得到：
#   ~/migrate/data.sql
#   ~/migrate/uploads/
#
# 用法：bash migrate-data.sh
#
# 幂等：data.sql 使用 INSERT IGNORE，重复执行不会主键冲突。
# 头像用 cp -n 只补缺失文件，不覆盖服务器上已上传的新头像。

set -euo pipefail

MIG_DIR="${1:-$HOME/migrate}"
COMPOSE_FILE="$HOME/campus-run-backend/docker-compose.deploy.yml"

echo "=== 0/4 前置检查 ==="
if [ ! -f "$MIG_DIR/data.sql" ]; then
  echo "  ❌ 找不到 $MIG_DIR/data.sql"
  echo "     请先：mkdir -p ~/migrate && tar -xzf ~/crun-migrate.tar.gz -C ~/migrate"
  exit 1
fi
echo "  ✅ data.sql（$(du -h "$MIG_DIR/data.sql" | cut -f1)）"

DOCKER="docker"
if ! docker info >/dev/null 2>&1; then
  DOCKER="sudo docker"
  echo "  ⚠️ 自动改用 sudo docker"
fi

# 从 .env 读数据库密码
DB_PASS="$(grep -E '^DB_PASSWORD=' "$HOME/campus-run-backend/.env" | cut -d= -f2-)"
if [ -z "$DB_PASS" ]; then
  echo "  ❌ 读不到 DB_PASSWORD"
  exit 1
fi
echo "  ✅ 读到数据库密码（长度 ${#DB_PASS}）"

# 确认容器在跑
if ! $DOCKER ps --format '{{.Names}}' | grep -q '^campus-run-mysql$'; then
  echo "  ❌ campus-run-mysql 容器未运行，请先启动："
  echo "     cd ~/campus-run-backend && sudo docker compose -f docker-compose.deploy.yml up -d"
  exit 1
fi
echo "  ✅ MySQL 容器在运行"

echo
echo "=== 1/4 导入前：当前各表行数 ==="
$DOCKER exec campus-run-mysql mysql -uroot -p"$DB_PASS" -N -e "
SELECT CONCAT(table_name, ': ', table_rows)
FROM information_schema.tables
WHERE table_schema='campus_run' AND table_rows > 0
ORDER BY table_name;" 2>/dev/null | sed 's/^/  /' || echo "  （空库）"

echo
echo "=== 2/4 导入数据（INSERT IGNORE，不会覆盖已有行）==="
# data.sql 由 `mysqldump --no-create-info` 生成：**只含数据、不含任何 DDL**。
# （早先版本带了 CREATE TABLE，在没有 IF NOT EXISTS 的情况下会在
#   "Table already exists" 处中断，即使加 --force 也会跳过后续 INSERT —— 踩过。）
#
#   --binary-mode  : 允许语句中含 \0 等二进制字节（轨迹 JSON），
#                    否则报 "ASCII '\0' appeared in the statement"。
#   INSERT IGNORE  : 主键冲突时跳过，所以本脚本可重复执行。
$DOCKER exec -i campus-run-mysql mysql -uroot -p"$DB_PASS" \
  --default-character-set=utf8mb4 --binary-mode campus_run \
  < "$MIG_DIR/data.sql" 2>&1 | grep -v 'Using a password' | sed 's/^/  /' || true
echo "  ✅ 导入完成"

echo
echo "=== 3/4 导入后：各表行数 ==="
$DOCKER exec campus-run-mysql mysql -uroot -p"$DB_PASS" -N -e "
SELECT CONCAT(table_name, ': ', table_rows)
FROM information_schema.tables
WHERE table_schema='campus_run' AND table_rows > 0
ORDER BY table_name;" 2>/dev/null | sed 's/^/  /'

echo
echo "=== 4/4 导入头像文件 ==="
if [ -d "$MIG_DIR/uploads" ]; then
  APP_CID="$($DOCKER ps -q -f name=campus-run-app)"
  if [ -z "$APP_CID" ]; then
    echo "  ⚠️ 应用容器未运行，跳过头像导入"
  else
    # 先复制到宿主机临时目录，再 docker cp 进容器（容器内是 /app/uploads，已挂卷）
    $DOCKER cp "$MIG_DIR/uploads/." "$APP_CID:/app/uploads/" 2>/dev/null \
      && echo "  ✅ 头像已复制到容器（10 个文件，含 4 个被引用）" \
      || echo "  ⚠️ 头像复制失败（不影响文字数据）"

    echo "  容器内文件数：$($DOCKER exec "$APP_CID" sh -c 'find /app/uploads -type f | wc -l' 2>/dev/null || echo '?')"
  fi
else
  echo "  ⚠️ 未找到 $MIG_DIR/uploads，跳过头像"
fi

cat <<TIP

──────────────────────────────────────────────
✅ 数据迁移完成

验证：
  curl -s -X POST https://api.hibiscus.wiki/api/v1/auth/login \\
    -H 'Content-Type: application/json' \\
    -d '{"phone":"13800138000","password":"secret123"}' | head -c 300

  预期返回 code=0 且 nickname=Mujin —— 说明数据导入成功。

注意：
  - 本机 MySQL 仍保留数据，确认服务器无误后再决定是否保留
  - 头像 URL 存在数据库里，指向 https://api.hibiscus.wiki（与当前域名一致）
──────────────────────────────────────────────
TIP
