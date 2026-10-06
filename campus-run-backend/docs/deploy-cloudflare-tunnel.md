# 用 Cloudflare Tunnel 让手机随处访问（最快方案）

**优点**：免费、不需要信用卡、不需要买服务器、**5 分钟可用**、自带 HTTPS。
**代价**：**电脑必须一直开着并联网** —— 隧道是从你电脑出去的。电脑休眠/关机，手机就连不上。

> 与 Oracle 免费服务器的取舍：
> - **想今天就跑** → 用本文（Cloudflare Tunnel）
> - **想要稳定、电脑不用开** → 见 `deploy-oracle.md`（真·公网，但注册要信用卡、要抢 ARM 配额）

---

## 一、准备（本机）

### 1. 安装 cloudflared

Windows 用 winget：

```powershell
winget install --id Cloudflare.cloudflared --accept-source-agreements --accept-package-agreements
```

⚠️ **国内常见失败**：`InternetOpenUrl() failed 0x80072efd` —— winget 从 GitHub 下载会超时。
此时改用国内镜像直接下（**实测可用**）：

```powershell
Invoke-WebRequest `
  'https://gh-proxy.com/https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe' `
  -OutFile "$env:USERPROFILE\cloudflared.exe"
```

验证（应输出 `cloudflared version 20xx.x.x`）：

```powershell
& "$env:USERPROFILE\cloudflared.exe" --version
```

### 2. 确认后端在跑

```powershell
Get-NetTCPConnection -LocalPort 8080 -State Listen
```

---

## 二、启动隧道

```powershell
& "$env:USERPROFILE\cloudflared.exe" tunnel --url http://localhost:8080 --no-autoupdate --protocol http2
```

从输出里找这一行（**注意别被别的 URL 迷惑**）：

```
INF |  https://xxxx-xxxx-xxxx.trycloudflare.com
```

### 两个实测踩到的坑

1. **第一次可能失败**：报
   `failed to request quick Tunnel: Post "https://api.trycloudflare.com/tunnel":
   context deadline exceeded (Client.Timeout exceeded while awaiting headers)`。
   **重试即可** —— 这是瞬时网络问题，不是被墙。
   可用 `cloudflared tunnel --url ...` 自带的 precheck 判断：全 PASS 就说明环境健康。

2. **`--protocol http2` 是必要的**：默认走 QUIC(UDP)，实测在部分网络下不稳定；
   强制 HTTP/2 后正常。（也可以用环境变量 `TUNNEL_EDGE_IP_VERSION=4` 强制 IPv4。）

> 💡 不要用正则去匹配日志里的 `https://...trycloudflare.com` 就完事 ——
> 日志里还有 `https://api.trycloudflare.com`（API 地址）和
> `https://developers.cloudflare.com/...`（提示链接），很容易匹配错。
> 要排除 `api.` / `developers.` / `www.` 前缀。

---

## 三、让后端返回的头像 URL 指向隧道

`PUBLIC_BASE_URL` 必须等于隧道地址，否则客户端拿到的头像 URL 打不开。

```powershell
$env:PUBLIC_BASE_URL = 'https://xxxx-xxxx-xxxx.trycloudflare.com'
# 然后重启后端
```

**已有的头像 URL 存在数据库里**（绝对地址），换地址后要一并更新：

```sql
UPDATE user
   SET avatar_url = REPLACE(avatar_url, '<旧地址>', '<新隧道地址>')
 WHERE avatar_url LIKE '<旧地址>%';
```

> 这是个**设计缺陷**：头像 URL 以绝对地址存库，换环境就失效。
> 正确做法是只存相对路径 `/uploads/avatar/xxx.png`，由客户端拼 baseUrl。待改造。

---

## 四、手机端

在 App 里点「**修改服务器地址**」（登录页底部，或启动页错误态里），填**不含 `https://`** 的地址：

```
xxxx-xxxx-xxxx.trycloudflare.com
```

`normalizeServerAddress()` 会自动补 `http://`。

> ⚠️ **这里有个已知限制**：`normalizeServerAddress` 只自动补 `http://`，
> 而隧道是 **https**。填纯域名会变成 `http://xxx.trycloudflare.com`。
> 如果连不上，**手动加上 `https://` 前缀**再保存。

---

## 五、安全性说明（重要）

隧道会把你的本机后端**暴露在公网上**，任何人都能用这个 URL 访问。当前缓解措施：

- 业务接口全部要 JWT（`/api/v1/**` 除登录注册外都需鉴权）
- 登录/注册/刷新有**入口限流**（手机号 10 次/5 分钟、IP 30 次/5 分钟）
- 隧道自带 HTTPS，JWT 不明文传输

**但仍然建议**：
- 调试完就停掉隧道（`Ctrl+C` 或结束 cloudflared 进程）
- 不要把它当作长期生产部署 —— URL 随机、无 uptime 保证，且你的电脑暴露在公网
- 长期方案用 `deploy-oracle.md`（或任意云服务器）

---

## 六、常见问题

| 现象 | 原因 |
|------|------|
| `failed to request quick Tunnel ... context deadline exceeded` | 瞬时网络故障，**重试**；或加 `--protocol http2` |
| winget 安装失败 `0x80072efd` | GitHub 被超时，用 `gh-proxy.com` 镜像直接下载 |
| 手机报网络错误，但电脑上 curl 隧道地址正常 | App 里地址缺少 `https://` 前缀 |
| 头像加载不出来 | `PUBLIC_BASE_URL` 不是隧道地址，或数据库里旧头像 URL 没更新 |
| 电脑一休眠就断 | 这是本方案的固有代价；把电源计划设为「从不休眠」可缓解 |

---

## 七、每次重启电脑后要做什么

云隧道的**免费随机 URL 每次都会变**，所以重启后要重复：

1. 启动后端（`PUBLIC_BASE_URL` 用新隧道地址）
2. 启动 cloudflared，拿到新地址
3. 更新数据库里的头像 URL（可选，只有头像会受影响）
4. 在 App 的服务器地址设置页填新地址

**想避免这个循环**：用 Cloudflare 账号创建**命名隧道**（URL 固定），
或用 Oracle 免费服务器（IP 固定）。见 `deploy-oracle.md`。
