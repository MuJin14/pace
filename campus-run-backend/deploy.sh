#!/usr/bin/env bash
# 行迹后端：一键部署（在 campus-run-backend/ 目录下执行）
#
# 前置：
#   1. 已执行 setup-server.sh
#   2. 代码已上传到服务器（git clone 或 scp）
#   3. .env 已按 .env.example 填好
#
# 用法：
#   cd campus-run-backend
#   cp .env.example .env   # 然后编辑 .env
#   bash deploy.sh
#
# 幂等：可重复执行（会重新构建并滚动重启）。

set -euo pipefail

cd "$(dirname "$0")"

COMPOSE_FILE="docker-compose.deploy.yml"

echo "=== 0/5 前置检查 ==="

# docker 命令前缀：usermod -aG docker 之后**当前会话不会立即生效**（需重新登录），
# 所以这里自动探测权限，不可用就回退到 sudo，避免卡在 permission denied。
DOCKER="${DOCKER:-}"
if [ -z "$DOCKER" ]; then
  if docker info >/dev/null 2>&1; then
    DOCKER="docker"
  elif sudo docker info >/dev/null 2>&1; then
    DOCKER="sudo docker"
    echo "  ⚠️ 当前用户无 docker 权限（usermod 后需重新登录才生效），自动改用 sudo"
  else
    echo "  ❌ 无法访问 docker：既无权限，sudo 也不可用"
    echo "     请先执行：bash setup-server.sh"
    exit 1
  fi
fi
echo "  ✅ Docker：$($DOCKER --version 2>/dev/null)"

# 兼容 v2 插件（docker compose）与独立二进制（docker-compose）
if $DOCKER compose version >/dev/null 2>&1; then
  DC="$DOCKER compose"
elif command -v docker-compose >/dev/null 2>&1; then
  DC="docker-compose"
else
  echo "  ❌ 未找到 docker compose 插件，请执行："
  echo "     sudo apt-get install -y docker-compose-plugin"
  exit 1
fi
echo "  ✅ Compose：$($DC version --short 2>/dev/null || true)"

if [ ! -f .env ]; then
  echo "  ❌ 缺少 .env —— 请先：cp .env.example .env 并填写"
  exit 1
fi
echo "  ✅ .env 存在"

# 校验关键变量非空且不是占位值
check_var() {
  local key="$1" val
  val="$(grep -E "^${key}=" .env | head -1 | cut -d= -f2- || true)"
  if [ -z "$val" ]; then
    echo "  ❌ .env 里 $key 为空"
    exit 1
  fi
  case "$val" in
    *CHANGE_ME*)
      echo "  ❌ .env 里 $key 还是示例值，请改成真实的"
      exit 1;;
  esac
  echo "  ✅ $key 已设置（长度 ${#val}）"
}
check_var DB_PASSWORD
check_var JWT_SECRET
check_var PUBLIC_BASE_URL

# JWT 密钥必须够长
jwt_len="$(grep -E '^JWT_SECRET=' .env | head -1 | cut -d= -f2- | wc -c)"
if [ "$jwt_len" -lt 33 ]; then
  echo "  ⚠️ JWT_SECRET 偏短（${jwt_len} 字符），建议 >= 32 字节。"
  echo "     生成：openssl rand -base64 48"
fi

echo
echo "=== 1/5 构建镜像（首次约 3-6 分钟）==="
$DC --progress plain -f "$COMPOSE_FILE" build

echo
echo "=== 2/5 启动（MySQL 健康后才起应用）==="
$DC -f "$COMPOSE_FILE" up -d

echo
echo "=== 3/5 等待应用就绪 ==="
ready=0
for i in $(seq 1 36); do
  sleep 5
  if curl -s -o /dev/null -m 5 http://localhost:8080/api/v1/auth/login -X POST \
      -H 'Content-Type: application/json' -d '{"phone":"1","password":"1"}'; then
    ready=1
    echo "  ✅ 应用已就绪（约 $((i*5)) 秒）"
    break
  fi
  echo "  ...等待中（$((i*5))s）"
done
if [ "$ready" -ne 1 ]; then
  echo "  ❌ 应用未就绪，最后 30 行日志："
  $DC -f "$COMPOSE_FILE" logs --tail 30 app
  exit 1
fi

echo
echo "=== 4/5 容器状态 ==="
$DC -f "$COMPOSE_FILE" ps

echo
echo "=== 5/5 验证 ==="
echo "  数据库表数量（应为 12）："
$DOCKER exec campus-run-mysql mysql -uroot -p"$(grep -E '^DB_PASSWORD=' .env | cut -d= -f2-)" \
  -N -e "SELECT COUNT(*) FROM information_schema.tables WHERE table_schema='campus_run';" 2>/dev/null \
  | sed 's/^/    /' || echo "    （查询失败，但应用已就绪）"

public_base="$(grep -E '^PUBLIC_BASE_URL=' .env | cut -d= -f2-)"
echo
echo "  本机接口测试（期望 HTTP 200，body 里 code 非 0 是正常的）："
curl -s -o /dev/null -w "    HTTP %{http_code}\n" -X POST \
  http://localhost:8080/api/v1/auth/login \
  -H 'Content-Type: application/json' -d '{"phone":"1","password":"1"}' || true

cat <<TIP

──────────────────────────────────────────────
✅ 部署完成

接下来的步骤：
  1. 【腾讯云控制台】安全组放行 8080（若还没做）
  2. 把域名 api.hibiscus.wiki 指向本机公网 IP：
     - 停掉本机的 cloudflared 隧道
     - Cloudflare DNS 里把 api.hibiscus.wiki 的 CNAME 记录
       改成 A 记录 → $(curl -s -m 5 ifconfig.me || echo '<本机公网IP>')
     - 或直接在服务商处改解析
  3. App 无需重新编译（地址仍是 https://api.hibiscus.wiki）

常用命令：
  看日志：docker compose -f $COMPOSE_FILE logs -f app
  重启：  docker compose -f $COMPOSE_FILE restart app
  停止：  docker compose -f $COMPOSE_FILE down
  备份库：$DOCKER exec campus-run-mysql mysqldump -uroot -p'***' campus_run > backup-\$(date +%F).sql

⚠️ PUBLIC_BASE_URL 当前为：$public_base
   它决定头像 URL，必须是客户端能访问到的公网地址。
──────────────────────────────────────────────
TIP
