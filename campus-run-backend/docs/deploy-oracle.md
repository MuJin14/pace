# Oracle Cloud Always Free 部署（详细步骤）

Oracle Always Free 是**真·永久免费**，规格足够跑这套栈（应用 441MB + MySQL 406MB）。
但它有几个**很容易卡住的坑**，本文按顺序列全。

> 只想快速上线：直接跳到「第 4 步：部署」之前先完成 1-3 步。

---

## 第 1 步：注册与创建实例

1. 注册 <https://www.oracle.com/cloud/free/> —— 需要**信用卡验证**（不会扣费，只验证）。
   - 地址信息建议如实填写；风控拒绝时换个邮箱/稍后再试是常见情况。
2. 登录后在左上角菜单 → **Compute → Instances → Create instance**。
3. 关键配置：

| 项 | 选择 | 原因 |
|---|---|---|
| **Image** | Canonical Ubuntu **22.04** 或 24.04 | 命令与本文一致 |
| **Shape** | **Ampere / ARM**，`VM.Standard.A1.Flex` | Always Free 里规格最好的（最多 4 OCPU / 24GB） |
| OCPU / 内存 | **1 OCPU / 6 GB** 就够 | 应用+MySQL 约 850MB，留足余量给系统 |
| **Boot volume** | 默认 47GB 够用 | |
| **SSH keys** | **保存好私钥**（下载的 `.key` 文件） | 丢了就得重装系统 |

> ⚠️ **ARM 实例常报 "Out of host capacity"**。这是 Oracle 免费层的常态，不是你的错。
> 解法：换个 Availability Domain（AD-2 / AD-3）试；或换区域；或过几小时/次日再试。
> 实在拿不到 ARM，就退而用 `VM.Standard.E2.1.Micro`（AMD，1GB 内存）——
> 但 1GB 跑这套栈会紧，需要把 `JAVA_OPTS` 调小（见文末「低内存调优」）。

4. 创建完成后记下**公网 IP**（Instance details → Public IP address）。

---

## 第 2 步：Oracle 的**双重防火墙**（最容易卡住的地方）

这是 Oracle 最常见的坑：**只开一层，外部就是连不上，表现为「浏览器打不开、超时」**。
两层都必须开：

### 第一层：云控制台的安全列表（Security List）

菜单 → **Networking → Virtual Cloud Networks** → 点你的 VCN → 点子网 →
**Security Lists** → 默认列表 → **Add Ingress Rules**：

```
Source Type:    CIDR
Source CIDR:    0.0.0.0/0
IP Protocol:    TCP
Destination Port Range: 8080
Description:    campus-run api
```

> 只想自己用、更安全的做法：`Source CIDR` 填你手机的出口 IP。但手机用 4G 时 IP 会变，
> 调试期先用 `0.0.0.0/0`，上线前收紧。

### 第二层：实例内部的 iptables（Ubuntu 镜像预置规则）

Oracle 的 Ubuntu 镜像**自带一条 REJECT 规则**，不处理它会前功尽弃。
SSH 登录实例后执行：

```bash
# 放行 8080（在 REJECT 规则之前插入）
sudo iptables -I INPUT 6 -m state --state NEW -p tcp --dport 8080 -j ACCEPT

# 持久化（重启后仍生效）
sudo apt-get update && sudo apt-get install -y iptables-persistent
sudo netfilter-persistent save
```

> 验证：`sudo iptables -L INPUT -n --line-numbers | head -12`
> 应能看到 8080 的 ACCEPT 排在 REJECT 前面。

**验证两层是否都通**（在你自己电脑上执行，不是服务器上）：

```bash
curl -i http://<公网IP>:8080/api/v1/auth/login -X POST \
  -H 'Content-Type: application/json' -d '{"phone":"1","password":"1"}'
```

- 返回 **HTTP 200** → 两层都通了 ✅
- **超时 / Connection refused** → 回去查上面两层，别继续往下做

---

## 第 3 步：安装 Docker

SSH 登录实例（用第 1 步下载的私钥）：

```bash
chmod 600 ssh-key.key
ssh -i ssh-key.key ubuntu@<公网IP>
```

```bash
curl -fsSL https://get.docker.com | sh
sudo usermod -aG docker $USER
newgrp docker          # 或退出重新登录
docker --version       # 验证
```

---

## 第 4 步：部署应用

在服务器上：

```bash
# 1. 拿到代码
git clone <你的仓库地址> campus-run
cd campus-run/campus-run-backend

# 2. 生成密钥并写入 .env
cp .env.example .env
echo "DB_PASSWORD=$(openssl rand -base64 24)"
echo "JWT_SECRET=$(openssl rand -base64 48)"
```

编辑 `.env`，把 `PUBLIC_BASE_URL` 改成服务器公网地址：

```ini
DB_PASSWORD=<粘贴上面生成的>
JWT_SECRET=<粘贴上面生成的>
PUBLIC_BASE_URL=http://<公网IP>:8080
CORS_ALLOWED_ORIGINS=http://localhost:8081
APP_PORT=8080
PUSH_ENABLED=false
```

```bash
# 3. 启动（首次约 3-6 分钟，ARM 上编译会稍慢）
docker compose -f docker-compose.deploy.yml up -d --build

# 4. 看状态与日志
docker compose -f docker-compose.deploy.yml ps
docker compose -f docker-compose.deploy.yml logs -f app
```

看到 `Started CampusRunApplication` 即成功。

```bash
# 5. 服务器本地验证
curl -i http://localhost:8080/api/v1/auth/login -X POST \
  -H 'Content-Type: application/json' -d '{"phone":"1","password":"1"}'
```

> 返回 HTTP 200 且 body 是 `{"code":1002,...}` 之类 → 服务通了（"用户不存在"是正常的）。

---

## 第 5 步：让 App 连上

**不需要重新编译 App。** 在手机上：

1. 打开校园跑
2. 点「**修改服务器地址**」（登录页底部，或启动页错误态里）
3. 填 `<公网IP>:8080`（**不用写 `http://`**，会自动补）
4. 保存 → 点「重试」→ 注册/登录

之后无论你在校园网、宿舍 WiFi 还是 4G，都能连上。

---

## 低内存调优（若用了 1GB 的 AMD 微实例）

1GB 内存跑两个容器会紧张。把 `.env` 加上，并在 compose 里给 app 传 `JAVA_OPTS`：

```ini
# .env
JAVA_OPTS=-XX:MaxRAMPercentage=55 -Xss512k -XX:+UseSerialGC
```

同时把 MySQL 限制一下（编辑 `docker-compose.deploy.yml` 的 mysql 服务）：

```yaml
    command:
      - --character-set-server=utf8mb4
      - --collation-server=utf8mb4_unicode_ci
      - --innodb-buffer-pool-size=128M
      - --performance-schema=OFF
```

> 建议还是争取 ARM 实例（6GB 起），省去这些折腾。

---

## 选配：HTTPS 与域名

公网跑 HTTP 意味着 JWT 明文传输，正式使用应上 HTTPS。
最省事的是加一个 Caddy 服务自动申请证书（见 `deploy.md` 末尾）。

---

## 常见问题速查

| 现象 | 原因 |
|---|---|
| 浏览器/curl 连不上，一直超时 | **两层防火墙**没配全（第 2 步）—— 这是第一嫌疑 |
| 容器反复重启 | 内存不足，看 `docker logs campus-run-app` |
| `Access denied for user 'root'` | 改了 `DB_PASSWORD` 但数据卷还是旧的密码 → `down -v` 重建 |
| 头像加载不出来 | `.env` 的 `PUBLIC_BASE_URL` 不是公网地址 |
| ARM 实例建不出来 | "Out of host capacity"，换 AD / 换区域 / 次日再试 |
| SSH 连不上 | 私钥权限太开放（`chmod 600`）或用户名不是 `ubuntu` |

## 备份

```bash
# 数据库
docker exec campus-run-mysql mysqldump -uroot -p"$DB_PASSWORD" campus_run > backup-$(date +%F).sql
# 上传的头像在 upload-data 卷里
docker run --rm -v campus-run_upload-data:/data -v $(pwd):/out alpine \
  tar czf /out/uploads-$(date +%F).tar.gz -C /data .
```
