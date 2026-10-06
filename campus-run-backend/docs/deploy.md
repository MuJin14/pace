# 部署指南（Campus Run 后端）

把后端部署到有**公网地址**的服务器上，手机就能用 4G/5G 访问，
不再受「必须和电脑同一个 WiFi」限制（校园网的 AP 隔离尤其致命）。

---

## 实测资源需求（决定选什么服务器）

在开发机上实测两个容器的稳定占用：

| 容器 | 内存 | CPU |
|------|------|-----|
| `campus-run-app`（Spring Boot） | ~441 MB | 0.1% |
| `campus-run-mysql`（MySQL 8） | ~406 MB | 0.7% |
| **合计** | **~850 MB** | 极低 |

**结论：至少 1 GB 内存，推荐 2 GB。**
512 MB 的免费额度会 OOM（Spring Boot 启动就要 300-400 MB）。
CPU 完全不是瓶颈，瓶颈只有内存。

---

## 一键部署（推荐：Docker Compose）

仓库已提供 `docker-compose.deploy.yml` + `Dockerfile`（多阶段构建、非 root 运行），
**已在本地完整实测通过**：MySQL 健康检查 → 自动建表 12 张 → 应用启动 7.1 秒 → 注册/登录/JWT 全部正常。

### 1. 准备服务器

需要一台 Linux 服务器（Ubuntu 22.04/24.04 均可），安装 Docker：

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER   # 重新登录后生效
```

### 2. 上传代码

```bash
# 在服务器上
git clone <你的仓库地址> campus-run
cd campus-run/campus-run-backend
```

> 若仓库是私有的，用 `scp -r` 从本地上传 `campus-run-backend` 目录。

### 3. 填写配置

```bash
cp .env.example .env
```

生成两个密钥（**不要用示例值**）：

```bash
echo "DB_PASSWORD=$(openssl rand -base64 24)"
echo "JWT_SECRET=$(openssl rand -base64 48)"
```

编辑 `.env`，把 `PUBLIC_BASE_URL` 改成服务器公网地址：

```ini
DB_PASSWORD=<上面生成的>
JWT_SECRET=<上面生成的>
PUBLIC_BASE_URL=http://<服务器公网IP>:8080
CORS_ALLOWED_ORIGINS=http://localhost:8081
APP_PORT=8080
PUSH_ENABLED=false
```

> ⚠️ `PUBLIC_BASE_URL` **必须**是客户端能访问到的地址 ——
> 它决定返回的头像 URL。填错的话头像会加载不出来（接口本身正常）。
> 有域名并配了 Nginx/HTTPS 就填 `https://your-domain.com`。

### 4. 启动

```bash
docker compose -f docker-compose.deploy.yml up -d --build
```

首次构建约 3-6 分钟（拉镜像 + Maven 编译）。

### 5. 验证

```bash
docker compose -f docker-compose.deploy.yml ps          # 两个容器都应 Up / healthy
docker compose -f docker-compose.deploy.yml logs -f app # 看到 Started CampusRunApplication
curl -i http://localhost:8080/api/v1/auth/login -X POST \
  -H 'Content-Type: application/json' -d '{"phone":"1","password":"1"}'
# 期望 HTTP 200（业务码非 0 是正常的，说明服务通了）
```

### 6. 开放防火墙

```bash
# 云厂商控制台的「安全组」也要放行 8080（这一步常被漏掉）
sudo ufw allow 8080/tcp
```

### 7. App 指向新服务器

在 App 的**服务器地址设置页**填 `http://<公网IP>:8080` 即可，**不用重新编译**。
（登录页底部与启动页错误态都有入口。）

---

## 常见问题

| 现象 | 原因 |
|------|------|
| 容器反复重启 | 内存不足（<1GB）。看 `docker logs campus-run-app` 是否有 OOM |
| `Access denied for user` | `.env` 里 `DB_PASSWORD` 与已建的 MySQL 数据卷不一致 —— 改了密码要 `down -v` 重建数据卷 |
| 头像 404 / 打不开 | `PUBLIC_BASE_URL` 填的不是公网地址 |
| 手机连不上、浏览器能开 | 云服务器**安全组**没放行 8080 |
| 数据卷删了后表没了 | `schema.sql` 只在**首次创建数据卷**时执行，这是 MySQL 镜像的标准行为 |

## 数据备份（重要）

```bash
docker exec campus-run-mysql mysqldump -uroot -p"$DB_PASSWORD" campus_run > backup-$(date +%F).sql
```

上传的头像在 `upload-data` 数据卷里，也要一并备份。

---

## 免费 / 低成本方案对比

| 方案 | 内存 | MySQL | 备注 |
|------|------|-------|------|
| **Oracle Cloud Always Free** | 最高 24 GB（ARM） | 可自建 | 真·永久免费，规格足够；注册需信用卡验证，过程较繁琐 |
| 阿里云 / 腾讯云学生机 | 2 GB | 可自建 | 约 ¥10/月，国内访问快、注册简单，**性价比最高** |
| Render / Railway 等 PaaS | 512 MB–1 GB | 需另配 | 免费额度普遍不够 850 MB，且闲置会休眠；数据库多为 PostgreSQL，需改造 |
| 内网穿透（cloudflared） | — | — | 把本机暴露到公网，零成本；但依赖本机一直开机 |

**推荐**：学生机（¥10/月，省心）或 Oracle Always Free（真免费，稍麻烦）。
PaaS 免费额度普遍是 512 MB，**跑不动这套栈**。

---

## 选配：HTTPS 与域名

生产环境应上 HTTPS（否则 JWT 在公网明文传输）。最省事的做法是
用 Caddy 反代（自动申请并续期证书），在 `docker-compose.deploy.yml` 旁再加一个 caddy 服务：

```yaml
  caddy:
    image: caddy:2
    restart: unless-stopped
    ports: ["80:80", "443:443"]
    volumes:
      - ./Caddyfile:/etc/caddy/Caddyfile:ro
      - caddy-data:/data
    networks: [campus-net]
```

`Caddyfile`：

```
your-domain.com {
    reverse_proxy app:8080
}
```

然后把 `.env` 里的 `PUBLIC_BASE_URL` 改成 `https://your-domain.com`、
把 `APP_PORT` 映射去掉（不再直接对外暴露 8080）。
