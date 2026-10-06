#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────
# certbot 续期后钩子：把新证书同步到 certs/ 并重启 Caddy。
#
# 为什么必须有这个钩子：
#   certbot 续期只更新 /etc/letsencrypt/live/... 下的文件，
#   而 Caddy 读的是挂载进容器的 /certs/le-fullchain.crt（一份**拷贝**）。
#   没有这个钩子的话，续期成功了 Caddy 也看不到新证书 ——
#   90 天后证书过期，表现为「突然全部 HTTPS 不可用」，而且很难联想到续期。
#
# 安装位置：/etc/letsencrypt/renewal-hooks/deploy/ （certbot 会在每次
#          成功续期后自动执行这个目录下的脚本）
# ─────────────────────────────────────────────────────────────────────
set -euo pipefail

LE=/etc/letsencrypt/live/api.hibiscus.wiki
CERTDIR=/home/ubuntu/campus-run-backend/certs
LOG=/var/log/letsencrypt/deploy-hook.log

echo "[$(date '+%F %T')] 开始同步证书" >> "$LOG"

cp "$LE/fullchain.pem" "$CERTDIR/le-fullchain.crt"
cp "$LE/privkey.pem"   "$CERTDIR/le-privkey.key"
chown ubuntu:ubuntu "$CERTDIR/le-fullchain.crt" "$CERTDIR/le-privkey.key"
chmod 644 "$CERTDIR/le-fullchain.crt"
chmod 640 "$CERTDIR/le-privkey.key"

# Caddyfile 里有 `admin off`，配置热重载（caddy reload）不可用 ——
# 必须重启容器才能加载新证书。重启只需 1~2 秒。
D=docker
docker ps >/dev/null 2>&1 || D="sudo docker"
$D restart campus-run-caddy >> "$LOG" 2>&1

# 自检：重启后 HTTPS 是否真的通了
sleep 3
code=$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 \
  --resolve api.hibiscus.wiki:8443:127.0.0.1 \
  https://api.hibiscus.wiki:8443/api/v1/app/version || echo "000")
echo "[$(date '+%F %T')] 续期后自检 HTTP $code" >> "$LOG"

# 证书剩余有效期（便于排查）
notafter=$(openssl x509 -in "$LE/fullchain.pem" -noout -enddate | cut -d= -f2)
echo "[$(date '+%F %T')] 新证书到期: $notafter" >> "$LOG"

if [ "$code" != "200" ]; then
  echo "[$(date '+%F %T')] 警告：自检未通过，请人工检查" >> "$LOG"
  exit 1
fi
echo "[$(date '+%F %T')] 完成" >> "$LOG"
