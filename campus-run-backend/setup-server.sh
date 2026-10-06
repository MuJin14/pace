#!/usr/bin/env bash
# 行迹后端：服务器环境准备脚本（Ubuntu 22.04 / 24.04）
#
# 用法（在服务器上执行）：
#   bash setup-server.sh
#
# 做三件事：
#   1. 配置 Docker 镜像加速器（国内拉 mysql:8.0 会超时，必须先配）
#   2. 安装 Docker
#   3. 放行防火墙 8080（云控制台的「安全组」还要单独放行，见输出提示）
#
# 幂等：可重复执行。

set -euo pipefail

echo "=== 1/3 配置 Docker 镜像加速器 ==="
sudo mkdir -p /etc/docker
sudo tee /etc/docker/daemon.json >/dev/null <<'EOF'
{
  "registry-mirrors": [
    "https://mirror.ccs.tencentyun.com",
    "https://docker.m.daocloud.io",
    "https://dockerproxy.com"
  ],
  "log-driver": "json-file",
  "log-opts": { "max-size": "10m", "max-file": "3" }
}
EOF
echo "  已写入 /etc/docker/daemon.json"
echo "  （第一个是腾讯云内网镜像，在腾讯云服务器上最快）"

echo
echo "=== 2/3 安装 Docker ==="
if command -v docker >/dev/null 2>&1; then
  echo "  已安装：$(docker --version)"
else
  curl -fsSL https://get.docker.com | sudo sh
  sudo usermod -aG docker "$USER"
  echo "  安装完成：$(docker --version)"
  echo "  （已把 $USER 加入 docker 组；当前 shell 需要用 sudo，或重新登录）"
fi

sudo systemctl enable --now docker
sudo systemctl restart docker
echo "  Docker 服务状态：$(systemctl is-active docker)"

echo
echo "=== 3/3 验证与提示 ==="
echo "  镜像加速测试："
sudo docker pull hello-world >/dev/null 2>&1 && echo "    ✅ 能拉镜像" || echo "    ⚠️ 拉取失败，检查网络"

echo
echo "  当前内存（应用+MySQL 约需 850MB）："
free -h | head -2 | sed 's/^/    /'

echo
echo "  当前磁盘："
df -h / | tail -1 | sed 's/^/    /'

cat <<'TIP'

──────────────────────────────────────────────
⚠️ 还需要在【腾讯云控制台】放行 8080 端口：
   控制台 → 你的实例 → 安全组 → 添加规则
     方向：入站
     协议端口：TCP:8080
     来源：0.0.0.0/0
     策略：允许
   否则外部永远连不上（这是最常见的问题）。
──────────────────────────────────────────────
TIP
