# 官网部署（hibiscus.wiki）

## 现状

| 项 | 值 |
|---|---|
| 站点根目录（宿主机） | `/home/ubuntu/campus-run-backend/site/` |
| 站点根目录（容器内） | `/srv/site`（只读挂载） |
| 对外地址 | `https://hibiscus.wiki:8443` |
| API 地址 | `https://api.hibiscus.wiki:8443`（**已修好，之前是 525**） |
| TLS 证书 | Cloudflare 源站证书 `certs/origin.crt`，**2041-09-30 到期** |
| Web 服务器 | Caddy（`caddy:2`，**不带** Cloudflare 插件） |
| DNS | 两个域名都走 Cloudflare 代理 |

## 改页面（不用重启任何东西）

```powershell
# 本地放好文件后
powershell -ExecutionPolicy Bypass -File campus-run-backend\deploy-site.ps1 -Password '<ssh密码>'
```

或者改一个文件时直接传：

```bash
scp index.html ubuntu@122.51.191.145:/home/ubuntu/campus-run-backend/site/
```

因为 `site/` 是**挂载目录**而不是打进镜像，改完立刻生效。

---

## ⚠️ 为什么是 `:8443` 而不是普通 `https://hibiscus.wiki`

服务器在**腾讯云境内**，域名**未备案** → 入站 **80/443 被拦截**
（实测 80 上带任意 Host 会拿到 401 或 webblock 页）。

非标准端口不受影响，所以对外统一走 8443，由 Cloudflare 代理进来。

**要让 `https://hibiscus.wiki` 直接可用**，需要在 Cloudflare 控制台：

1. **DNS**：`hibiscus.wiki` 的 A 记录改成 `122.51.191.145`
2. **Rules → Origin Rules → Create**：
   - When incoming requests match: `Hostname equals hibiscus.wiki`
   - Then: **Destination Port = 8443**，Host header = 保留
3. **SSL/TLS 模式必须是 `Full` 或 `Full (strict)`**

> ⚠️ **不能用 Flexible**：Flexible 会让 Cloudflare 用 `http://` 回源，
> 而源站这个站点只在 8443 上提供 **HTTPS**，会直接 522/525。

⚠️ 还有一个坑：Cloudflare **免费版**的 Origin Rules 有配额，
而且回源端口必须在它允许的列表里（8443 是允许的）。
如果配不上，退一步就用带端口的地址 `https://hibiscus.wiki:8443`。

---

## ⚠️ 修过的 3 个真实故障

### 1. `api.hibiscus.wiki:8443` 一直 525（TLS 握手失败）

服务器上的 Caddyfile 是：

```caddyfile
api.hibiscus.wiki:8443 {
    tls {
        key_type rsa2048      # ← 没有 dns 指令，也没有 cert/key
    }
}
```

Caddy 于是去申请 Let's Encrypt 证书。但：

- `http-01` / `tls-alpn-01` 需要 80/443，而那两个端口被拦
- `dns-01` 需要 **Cloudflare DNS 插件**，而服务器跑的是**上游 `caddy:2`，没有这个插件**
  （repo 里虽然有个 `Dockerfile.caddy-dns`，但**服务器上根本没这个文件**）

三条路全断 → 签发失败 → 握手报 `alert 80` → Cloudflare 返回 **525**。

**修法**：改用 Cloudflare **源站证书**（`/certs/origin.crt`）：

```caddyfile
(origin_tls) {
    tls /certs/origin.crt /certs/origin.key
}
```

好处：**不需要任何插件、不依赖 CF_API_TOKEN、到 2041 年才过期、没有续期问题**。
浏览器看到的证书由 Cloudflare 边缘提供，源站这张只在 Cloudflare → 源站 之间用。

> 这也解释了为什么 `certs/` 目录一直存在却从未被使用 —— 它是为此准备的，
> 但配置一直没接上。

### 2. MySQL 无限重启：`unknown variable 'character-set-client=utf8mb4'`

```yaml
command:
  - --character-set-server=utf8mb4
  - --character-set-client=utf8mb4      # ← mysqld 服务端不认这个选项！
```

`--character-set-client` / `--character-set-connection` / `--character-set-results`
**只有 mysql 客户端认**，`mysqld` 服务端会报 `[ERROR] [MY-000067] unknown variable`
然后**立刻 abort** → 容器 `Restarting (1)` 死循环。

这个配置**从写下的那天起就是错的**，但只有在容器被重建时才暴露 ——
之前一直没重建过，所以潜伏了很久。

**修法**：删掉整个 `command:` 块，改用官方环境变量（entrypoint 会写成配置文件，
`mysqld` 必定接受）：

```yaml
environment:
  MYSQL_DATABASE: campus_run
  MYSQL_INITDB_SKIP_TZINFO: "1"
  LANG: C.UTF-8
  TZ: Asia/Shanghai
```

> 字符集仍然必须是 utf8mb4 —— 否则首次初始化 `schema.sql` 时中文会被
> 当成 latin1 再编码一次（档案里记载过的「勋章墙乱码」就是这个成因）。

### 3. compose 拒绝重建任何容器

```yaml
environment:
  CF_API_TOKEN: ${CF_API_TOKEN:?必须在 .env 里设置 CF_API_TOKEN}
```

`${VAR:?msg}` 是**强制必填**，而 `.env` 里**根本没有这个变量** →
compose 直接报错退出 → **caddy 容器永远重建不了**，配置改了也白改。

**修法**：新版配置不需要 DNS-01，把这个变量整个删掉。

> 这是「repo 的 compose 和服务器上的 compose 已经漂移」的典型后果：
> repo 里加了新变量，服务器上没同步；而服务器上多了个强制必填，repo 里没有。

---

## App 已切到 HTTPS（2026-10-05，v1.2.0）

| 项 | 值 |
|---|---|
| App 访问地址 | `https://api.hibiscus.wiki:8443` |
| 老版本兼容 | `http://122.51.191.145:8080` **保持不动**，1.1.0 及更早照常可用 |
| 图片 URL 前缀 | `PUBLIC_BASE_URL=https://api.hibiscus.wiki:8443` |
| WebSocket | 自动 `https://` → `wss://`（`global_ws_provider.dart`），实测 **101 Switching Protocols** |

### 这是「叠加」不是「替换」

切换时**没有**关掉 8080 明文通道。原因是：

- 旧版本 App 硬编码了 `http://122.51.191.145:8080`，关掉等于让所有老用户失联
- 两条路指向**同一个 app 容器**，只是入口不同
- 还能当后路：万一 Cloudflare 出问题，可在 App 内「修改服务器地址」切回 IP

### 切换前必须验证的 3 件事（都实测过）

1. **WebSocket 经 Cloudflare 能否升级** —— 聊天全靠它。
   用原生 socket 发 `Upgrade: websocket` 验证，得到 `101`。**只看 200 不够**：
   鉴权失败也会返回 200，那会掩盖真实问题。
2. **图片经 HTTPS 能否取到** —— 换域名后老 URL 会失效。
   实测 4 个头像经 HTTPS 全部 200。
3. **跨协议下载** —— 1.1.0 走 http，而 `apkUrl` 是 https。
   下载用的是**独立 Dio 实例、绝对 URL**，不受 `baseUrl` 协议影响。已实测 53.6MB 下载成功且 SHA256 一致。

### `PUBLIC_BASE_URL` 必须一起改

它决定服务端返回的图片 URL 前缀。只改 App 不改它会得到
`http://122.51.191.145:8080/uploads/...` —— 在 HTTPS 页面里属于混合内容。
（Flutter 原生不拦明文图片，所以不会立刻报错，但 Web 端会被拦。）

已有数据也做了迁移：

```sql
UPDATE user SET avatar_url = REPLACE(avatar_url,
  'http://122.51.191.145:8080/', 'https://api.hibiscus.wiki:8443/')
 WHERE avatar_url LIKE 'http://122.51.191.145:8080/%';
-- message.media_url 同理（当时 0 条）
```

## 最终架构（2026-10-05）

```
hibiscus.wiki            → Cloudflare Workers 静态托管     官网（快、免备案）
dl.hibiscus.wiki:8443    → 直连服务器 Caddy                APK 下载（53.8 MB）
api.hibiscus.wiki:8443   → Cloudflare 代理 → Caddy → app   App 全部接口
```

### ⚠️ 为什么 APK 不能放 Workers

**Workers 静态资源有 25 MiB 单文件硬限制**，免费和付费都一样。
APK 是 53.8 MB，上传时直接报错：

```
共 10 个文件正在上传
  ❌ 1/10 个文件无法上传:
     1 超过 25 MiB 的文件大小限制。请减小这些文件的大小，然后重试。
     campus-run.apk
```

这是**平台限制**，不是配置问题 —— 不要在这上面浪费时间。
解决办法是把 APK 放在自己的服务器，用独立子域名下载。

### `dl` 子域名的 DNS 必须设成「仅 DNS」（灰云）

- 灰云 = 不经过 Cloudflare → **没有 25MB 限制、不需要备案**
- 端口用 **8443**（境内未备案域名的 80/443 会被拦截）
- 浏览器会对源站证书提示「不安全」—— 那张是 Cloudflare 源站证书，
  不在公共信任列表里。下载页已经写明「点继续访问即可」。

### ⚠️ 新增站点块必须 `--force-recreate`

Caddy **不会**自动加载新增的站点块。加完 `dl.hibiscus.wiki:8443` 后，
`caddy validate` 通过、容器内文件也可读，但请求 `/style.css` 返回
**HTTP 200 + 0 字节**（旧的站点块仍正常）。

必须：

```bash
docker compose -f docker-compose.deploy.yml up -d --no-build --no-deps --force-recreate caddy
```

`deploy-site.ps1` 已经内置。`--no-deps` 保证不会连带重建 mysql/app。


## 图片缩略图（2026-10-05）

### 问题

用户反馈「加载图片巨慢」。根因不是网络波动，而是两个事实叠加：

1. 服务器上行带宽只有约 **0.2–0.46 MB/s**（实测多段下载取平均）；
2. 聊天图上限 2MB，且**服务端完全没有缩略图** —— 列表里每张都拉原图。

一张 1.5MB 的图 = 5–10 秒。一屏几张就是几十秒。

### 解法

`GET /api/v1/media/thumb?path=chat/ab12.jpg&w=400`

- `ThumbnailService` 读原图 → 缩放 → 编码 JPEG → 落盘缓存；
- 缓存键 = 相对路径 + 宽度 + **原文件 mtime + size**，
  所以原图被替换时不会读到旧缩略图；
- 不改数据库：老数据（已存成绝对 URL 的那些）立刻受益。

**实测效果**（239KB 头像）：

| | 大小 |
|---|---|
| 原图 | 239,020 字节 |
| 缩略图 w=200 | 22,105 字节（**缩小 10.8 倍**） |
| 缩略图 w=400 | 66,899 字节 |

### 安全（这个接口是**匿名可访问**的）

它替代 `/uploads/**` 的角色（`<img>` 不带 Authorization 头），
所以路径穿越防护是硬要求 —— 否则就是任意文件读取：

- `normalize()` 之后必须 `startsWith(uploadRoot)`；
- 宽度夹在 32–1600，不能当「原图放大器」或 DoS 入口；
- 失败一律返回 **404 而非 500**：客户端据此退回原图，是预期降级路径。

实测 `../../etc/passwd`、URL 编码变体、`chat/../../../etc/passwd` 全部 404。

## 断网与偶发失败的自动重试（2026-10-05）

用户反馈「进聊天记录，第二次失败、第三次成功、第四次又失败」——
典型的偶发失败，根因是 **`receiveTimeout` 只有 10 秒且全链路无重试**。

`RetryInterceptor`：

- 只重试 **GET / HEAD / OPTIONS**。带 Authorization 的写请求一律不重试 ——
  重复发消息、重复上传运动记录都是用户能直接看到的后果。
- 只重试网络类错误与 502/503/504/408/429；
  其它 4xx 重试一百次也一样，只会浪费用户流量。
- 指数退避 400ms → 800ms + 抖动，最多 3 次。
- `receiveTimeout` 同时从 10s 放宽到 20s（大图正好卡在 10s 边缘）。

## 手机号校验必须与后端一致（2026-10-05）

用户反馈「输入 11111111111 报参数错误，换别的 11 位数字却没问题」。

**不是后端 bug**：后端规则是 `^1[3-9]\d{9}$`（第二位须为 3–9，
这是真实运营商号段规则），`11111111111` 第二位是 `1`，本就该拒绝。

**是我们自己的问题**：App 的 `Validators.validatePhone` 只校验
`^\d{11}$`，比后端宽松 —— 于是坏号码通过了本地校验、发到后端才被拒，
而界面上只显示一句笼统的「参数错误」，用户完全看不出原因。

**教训**：本地校验比后端宽松 = 把准确报错的机会浪费掉，只剩一个通用错误码。
两者必须完全一致（手机号 / 密码长度 / 昵称长度都已对齐）。


## 登录页「会跑的跑道」动效（2026-10-05）

用户提出：「运动软件界面太静态，想让顶部波浪动起来，
把它想象成跑道，上面放一个小圆点代表人，波浪循环滚动、小人原地不动。」

这正是 2D 游戏里的**侧滚错觉（parallax scrolling）**：跑道向左匀速滚动，
小人在画面上固定，看起来就在一直往前跑。实现见
`lib/core/widgets/auth_scaffold.dart` 的 `_RunningTrackPainter`。

### 三个必须同时成立的条件（少一个就露馅）

1. **循环必须无缝。** 跑道是两个正弦叠加，位移量取**一个完整周期**
   （`_shift => progress * 1.0`）。1 倍频与 2 倍频在整周期位移下同时回到原位，
   所以循环点画面完全连续。用随机折线或非整数位移会看到明显跳变。

2. **小人必须真的贴在跑道上。** 它的 y 不是常数，而是用**同一个波形函数**
   在固定 x（0.52）处求出来的；圆心再下移「半径 + 半个线宽」，
   让它看起来是踩在线上而不是浮在空中。

3. **小人本身要几乎不上下移动。** 侧滚错觉的关键是「横向在动、纵向不动」。

第 3 点是被测试逼出来的：最初振幅用 0.16 / 0.055，
`running_track_test.dart` 算出小人在一个循环里上下移动 **68px**
（背景总高只有 190px）—— 那是在跳，不是在跑。振幅压到 0.072 / 0.026 后
降到约 31px，才是「沿跑道轻微起伏」。

同理，小圆点半径从 0.026 调到 0.020：按精确几何算，0.026 时半径 28px
而跑道半线宽只有 16px —— 圆点比线还粗，视觉上和跑道脱开成一团。

### 无障碍

`MediaQuery.disableAnimationsOf` 为真时（系统「减弱动态效果」开关）
**必须停止滚动**，只画静态跑道。前庭功能敏感的用户会因持续运动的背景不适，
这不是可选项。

### 几何验证方式

`test/running_track_test.dart` 用数学断言守住上面三条
（循环重合、起伏幅度上限与下限、波形不越界），
不依赖截图 —— 这种「看着有点怪」的问题最容易在改动中被忽略。

## 状态栏图标在浅色背景上不可见（2026-10-05）

用户换成极简白底后，状态栏的时间/电量几乎看不见。

根因：App 是浅色主题，但**从未声明 `SystemUiOverlayStyle`**，
系统沿用默认（深色主题下是浅色图标）→ 白字画在奶油白底上。

这个问题一直存在，只是**以前登录页顶部是一大块橙色渐变**，
白图标在橙底上正好可见，把它掩盖住了。

修法：只在 `AppBarTheme.systemOverlayStyle` 里设是**不够的** ——
那只对带 AppBar 的页面生效，而登录页/注册页/启动页都没有 AppBar。
必须在 `MaterialApp.router` 外面套一层
`AnnotatedRegion<SystemUiOverlayStyle>` 才全局生效。

## 协议条文点不开（2026-10-05）

登录页与注册页都有「我已阅读并同意《用户协议与隐私政策）》」勾选框，
协议名可点。但点了**没有任何反应**。

根因：路由守卫 `resolveRedirect` 的放行名单里没有 `/privacy`。
未登录时它把用户重定向回 `/login` —— 看起来就像点击没生效。

这是**合规问题**而不只是体验问题：《个人信息保护法》与应用商店审核
要求注册/登录前能查阅协议全文，点不开等于强迫用户盲勾同意。

修法：把 `/privacy` 加入两处放行名单（未登录时、以及网络异常时），
并补了 3 个守卫用例。实测去掉修复后正好失败 2 个。

## 协议正文残留 ** 星号（2026-10-05）

协议正文用 `**粗体**` 标注重点（如「仅在**你主动点击「开始跑步」后**才采集定位」），
但正文是当纯字符串渲染的，页面上出现了**字面的星号** ——
看起来像没写完的草稿，也削弱了本该强调的合规表述。

修法：加一个只认 `**` 的极小解析器（`_RichBody`），
没必要为它引入 markdown 依赖。`test/privacy_policy_test.dart`
断言页面上不存在字面星号、且关键表述确实是粗体。


## 跑道动效的定位方法：按真机实测反推（2026-10-05）

用户反复反馈「跑道位置不对」——先太靠上、再太靠下、后又离眼睛太远。
前几轮我一直在**试参数**，来回改了六次。后来用户直接给了正确做法：

> 「直接读取停留在输入框时候 logo 的位置，以此为基础设置圆点，
>   再以此为基础设置跑道」

### 做法

1. `adb shell screencap` 截真机图；
2. 用 numpy 找**品牌橙 `#FF8C42`** 的像素，按行统计做垂直分段，
   得到每个橙色元素的精确包围盒；
3. 手机 DPR=3，物理像素 ÷ 3 = Flutter 逻辑像素。

实测（1200×2670）：

| 元素 | 物理 y | 逻辑 y |
|---|---|---|
| 跑道段 | 244..338（中心 291） | 97 |
| logo 段 | 429..475（中心 452） | 151 |
| 登录按钮 | 895..1052 | 308 |

于是把跑道基线定为 `97 / 280 ≈ 0.35`（容器高 280 逻辑），
圆点落在基线下方 `1.15 × 线宽`（约 37px）—— 正好填在
「跑道」与「logo」之间那段空隙里。

### 教训

**能测量的就不要试。** 这个值试了六轮都没对，测一次就定位了。
凡是「位置/间距/尺寸」类问题，只要界面上有已知参照物，
就应该去量而不是猜。


## 头像也必须走缩略图（2026-10-05）

用户反馈：「头像部分是不是也一直用的原图？有些头像会加载一会再显示」。

**是的，而且这是我上一轮的遗漏。** 加缩略图接口时只改了聊天图片，
漏了头像 —— 而头像出现在好友列表、排行榜、聊天、搜索结果等
**每一条列表项**里，一屏十几张。

实测（同一张头像）：

| 尺寸 | 字节 |
|---|---|
| 原图 | 239,020 |
| w=96 | 6,601（**缩小 36 倍**） |
| w=144 | 12,873 |
| w=192 | 20,412 |

### 修法

`UserAvatar` 按**显示尺寸 × 设备像素比**请求缩略图，
再向上归整到 32 的倍数：

```
size 40 × dpr 3 = 120  ->  w=128
size 44 × dpr 3 = 132  ->  w=160
size 46 × dpr 3 = 138  ->  w=160   （与 44 同档，共用缓存）
size 64 × dpr 3 = 192  ->  w=192
size 84 × dpr 3 = 252  ->  w=288
```

按物理像素取是为了高分屏不发虚；归整到 32 的倍数是为了让
「46 与 44」这类相邻尺寸命中同一份缓存，不重复下载。

另外加了 `frameBuilder`：加载中先显示昵称首字兜底，
而不是留一块空洞再突然跳成头像 —— 后者也是「加载一会才显示」观感的一部分。

### 测试

`test/user_avatar_test.dart` 断言**请求的 URL 必须是缩略图接口**。
这是个很容易被改回去的优化：谁顺手把 `thumb ?? resolved` 改成 `resolved`，
界面不会报错、只是变慢，代码评审也看不出来。
实测去掉修复后正好失败 5 个用例。


## 版本徽章不更新：一个静默失败（2026-10-05）

**现象**：官网上的版本徽章长期停在 `1.4.1`，而 APK 已经发到 1.7.0。

早期排查时我把它归因于「部署脚本取版本失败 / version.json 陈旧」——
**归因错了**。`version.json` 一直是新的，问题出在**烘焙步骤从未执行**。

### 根因

```powershell
$Root   = <repo>\campus-run-backend
$embed  = Join-Path $Root 'tools\embed_site_version.py'
if (Test-Path $embed) { ... }        # ← Test-Path 为假，整块被静默跳过
```

而脚本实际在 **仓库根** 的 `tools/` 下，不在 `campus-run-backend/tools/`。
一层路径之差 → `Test-Path` 为假 → `if` 块整体不执行 → **没有任何输出**，
所以既看不到报错，也看不出被跳过。

这和本文件前面记过的另一条是同一类问题：
`Invoke-Remote` 被定义在文件后半段、前面调用它时抛异常被 catch 吞掉，
于是 version.json 悄悄保持旧值。**两次都是「catch/条件判断吃掉了失败」。**

### 修法

1. 同时尝试两个候选路径（仓库根优先，兼容子目录）；
2. **找不到就大声警告**，并打印它找过的每个路径；
3. 找到时也打印脚本与 python 的实际路径，让日志能自证这一步真的跑了。

现在的部署输出长这样，一眼就能确认：

```
=== Bake version into HTML + cache-bust assets ===
  embed script: C:\Users\...\project\tools\embed_site_version.py
  python: C:\Users\...\Python312\python.exe
  embedded v1.7.0  54.1 MB
```

### 顺带

该文件里新增的一行注释带了 emoji（`\u26a0\ufe0f`），
立刻导致 PowerShell 5.1 解析报错 —— 再次印证「**这个脚本必须保持纯 ASCII**」这条铁律。


## 「点开始跑步后要等很久」的两个原因（2026-10-05）

用户反馈：「为什么点击开始跑步后那个定位需要那么久」。

### 原因一：预热取点用错了精度（上一轮我自己引入的）

为了修「定位开关没开却静默卡住」，我加了一次预热取点：

```dart
await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.low,   // 错
  timeLimit: const Duration(seconds: 12),  // 也错
);
```

- `LocationAccuracy.low` 在 Android 上**通常不用 GPS**，而是靠 Wi-Fi/基站做
  单次定位 —— 反而比 `high` 更慢。而追踪流本身用的是 `high`，等于白等一次。
- 12 秒超时意味着最坏情况下先干等 12 秒，之后才开始真正的定位。

**修法**：预热改用 `high`，超时收紧到 **4 秒**。
这一步的职责只是「区分服务是否被关闭」——服务关着时
`LocationServiceDisabledException` 是**立即**抛出的，等不到超时，
所以短超时完全不影响判断；而服务开着时会很快返回。

### 原因二（更严重）：界面提前切到了「跑步中」

```dart
final ok = await _requestPermission();
if (!ok || !mounted) return;
setState(() => _phase = _Phase.ready);   // ← 还没拿到任何定位点就切了
_startTracking();
```

权限一通过就显示完整的跑步界面：计时器在走、距离是 0、没有轨迹。
而 `TrackSampler` 还在过滤精度不够的定位点，
**要等第一个「合格」点才有任何反应**，最坏 45 秒。

界面看起来「已经在跑了」但数据全是 0，比停在「正在获取定位…」更让人困惑。

**修法**：保持在「正在获取定位…」，由 `_onPosition` 收到首个合格点后
再切 `ready`，**计时器也从那一刻启动** ——
这样「用时」与「轨迹」天然对齐，不会出现「时间走了但没距离」。

### 教训

「先放行、后面再纠正」这种写法在**有耗时前置条件**的流程里很危险：
它把等待从「有明确反馈的等待」变成了「看起来已经在跑、但没有数据」，
用户的感受反而更差。等待本身不可怕，**不知道在等什么才可怕**。


## 桌面图标与应用信息页显示不一致（2026-10-05）

用户反馈：「App 桌面的图标和点开应用信息时图标不一样」。

### 根因：两套图标资源的外观不同

Android 的图标有两条路径，取决于系统版本与所处界面：

| 界面 | 使用的资源 |
|---|---|
| 启动器（API 26+） | `mipmap-anydpi-v26/ic_launcher.xml`（自适应图标） |
| 应用信息页 / 旧版启动器 | `mipmap-*/ic_launcher.png`（legacy 位图） |

两者内容相同（都是那条行进轨迹），但**底不一样**：

- legacy PNG：生成脚本画的**对角渐变** `#FF8C42 -> #F0653A`；
- 自适应图标：`<background android:drawable="@color/ic_launcher_background" />`，
  而那个 color 只有 **一个纯色** `#FF8C42`。

于是同一个 App 在两处显示两种底色。量化对比：内容占比都是 96%，
差别纯粹在「纯色 vs 渐变」。

### 修法

1. 把 `values/ic_launcher_background.xml`（纯色）换成
   `drawable/ic_launcher_background.xml`（`<shape>` + 对角渐变），
   端点与 PNG 完全一致，自适应图标引用它；
2. 补上 `android:roundIcon="@mipmap/ic_launcher_round"` ——
   之前只声明了 `icon`，圆形图标主题会退回用方形图再被系统裁圆。

### 顺带发现的坑：图标缓存

改完直接 `adb install -r` 覆盖安装，**桌面图标没有变化** ——
启动器与 Settings 都会缓存图标。必须
`adb uninstall` + 重新 `install`（或 `pm clear` 启动器）才会刷新。
排查这类「改了没生效」的问题时，先排除缓存，否则会误判成改动无效。

### 另一个坑：XML 注释不能写在属性中间

我第一次把说明注释插在 `android:icon` 与 `android:roundIcon` 两个属性之间 ——
**这是非法 XML**。注释只能出现在元素之间，不能出现在起始标签的属性列表里。
已移到 `<application>` 之前，并加了 `xml.dom.minidom.parse` 校验。


## 官网改版与两个「静默吃代码」的坑（2026-10-05）

应用改动累积了很多，官网还停在最早那版（品牌还叫「校园跑」）。
借这次改版把内容全部对齐，并顺手查出两个会**静默吞掉页面代码**的问题。

### 一、embed_site_version.py 会删掉页面脚本

原来的替换规则：

```python
html = re.sub(r"<script>\n// 版本[^\x00]*?</script>", '', html)
```

它锚定在**裸标签**上（`<script>` + 中文注释），而不是 id。
只要页面里出现别的普通 `<script>` 块（首屏跑道动画、更新日志淡入），
这个正则就会把它们当成「旧的版本脚本」一并删掉 ——
**每次部署都在悄悄删页面代码，而且没有任何报错**。

改版时加了两段脚本，部署后更新日志整段是空白的，才发现。

**修法**：

1. 版本脚本加 `id="ver-badge"`，按 id 精确替换，不再匹配周围标记；
2. 加**内容护栏**：写入前断言页面仍包含必需内容
   （JS 标记、跑道装饰、更新日志脚本、版本接口），
   以及 `<script>` 开闭标签数量一致；缺任何一项就
   `SystemExit` 拒绝写入 —— **拒绝部署远好过悄悄发布一个坏页面**。

护栏有效性已验证：故意删掉一段脚本时，脚本报
`REFUSING TO WRITE: the page lost required content.` 并指出缺了哪一项。

### 二、淡入动画把内容藏成了不可见

更新日志初始 `opacity: 0`，靠 `IntersectionObserver` 加 `.in` 才显示。
这等于**把「内容能否显示」押在 JS 上** —— 脚本没跑、被拦截、
或观察器静默失效时，整段内容永久不可见，且不报任何错。

**修法（渐进增强）**：

- 在 `<head>` 最前面给 `<html>` 加 `class="js"`，
  淡入样式写成 `.js .clog-item { opacity: 0; ... }` ——
  JS 不可用时内容照常显示；
- 观察器加三层兜底：不支持 `IntersectionObserver` → 全部显示；
  创建失败 → catch 里全部显示；**2 秒后仍没显示的强制显示**
  （无头截图、浏览器打印、观察器降级都会走这条）。

### 三、顺手修掉的移动端隐患

首屏的手机模型与「连续打卡 7 天」浮动卡片是**刻意超出容器**画的
（`.float-a { right: -6px }`），窄屏上会撑出横向滚动条、右侧内容被切。

- `html` 与 `body` 同时 `overflow-x: hidden`
  （只写 body 时某些浏览器仍以 html 为准）；
- 640px 断点把浮动卡片收进容器（`right: 0`），手机模型 250 → 210px；
- 新增 380px 断点，模型进一步降到 186px。

### 四、一条测试环境的教训

用 headless Chrome 的 `--window-size` 量窄屏布局**不可靠**：
它会强制一个约 800px 的最小视口再裁图，于是 640px 的媒体查询
根本没生效，量出来的「溢出」是环境假象。
**判断移动端布局必须用真机，或者能真正覆盖视口的 CDP 指标**，
否则会照着假象改 CSS。

## 关键教训

### 服务器上的 compose / Caddyfile 是**手工维护的**，部署脚本不会覆盖

`deploy-server.ps1` 只上传 `pom.xml` + 两个模块的 `src`。
服务器上的 `docker-compose.deploy.yml` 含生产专属内容（证书挂载、端口），
**刻意不从 repo 覆盖**。

**所以往 repo 的 compose 里加挂载或环境变量之后，必须手工同步到服务器**，
否则症状是「代码是新的，但配置没生效」。

### 改容器配置前先手动跑一次 `docker compose up -d --no-build <svc>`

不能只在脚本里跑。脚本如果用 `| tail` 包装，**退出码会变成 `tail` 的 0**，
失败被吞掉 —— 我因此得到过一次「假成功」，还打印了 DONE。

正确写法：

```powershell
$out = docker compose ... 2>&1
$code = $LASTEXITCODE        # 在管道之前取
if ($code -ne 0) { ... }
```

### 容器重建前先备份 compose，并**验证新配置**

```bash
cp docker-compose.deploy.yml docker-compose.deploy.yml.bak-$(date +%s)
docker compose -f docker-compose.deploy.yml config --quiet   # 语法与变量插值
```

`deploy-site.ps1` 已经内置：备份 → 上传到 staging → `caddy validate` →
安装 → 重建 → 健康检查（失败自动回滚 Caddyfile）。
