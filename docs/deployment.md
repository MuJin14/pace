# 部署

> 一键脚本：`../campus-run-backend/deploy-server.ps1`（后端）、
> `release-apk.ps1`（App 发版）、`deploy-site.ps1`（官网）。
> 详细流程与踩坑见 `campus-run-backend/docs/release.md` 与 `site.md`。


## 部署要点（从各轮记录中收拢，这里是唯一权威副本）

### 部署方式（重要：服务器是**源码构建**，不是传 jar）

`docker-compose.deploy.yml` 的 app 服务是 `build: context: .`（多阶段 Dockerfile），
**服务器上没有 `target/*.jar`** —— 部署必须上传**源码**，由 Docker 内 `mvn package` 编译。

用 [`../campus-run-backend/deploy-server.ps1`](../campus-run-backend/deploy-server.ps1)：

```powershell
powershell -ExecutionPolicy Bypass -File campus-run-backend\deploy-server.ps1 -Password '<ssh密码>'
```

⚠️ **踩过的坑**（脚本已规避，改脚本时注意）：

- **`Compress-Archive` 不保留 Unix 权限**：解压出来的目录是 `drw-rw-r--`，
  **缺 `x`（遍历）位**，导致 `cp`/`ls` 全部 `Permission denied`，
  而 `touch`/`rm` 却正常 —— 极具误导性。解压后必须
  `find . -type d -exec chmod 755 {} +`。
- **本机是 Windows PowerShell 5.1**（不是 pwsh 7）：
  - 不支持 `||` / `&&` 语句分隔符；
  - **无 BOM 的 UTF-8 脚本会被当 GBK 读**，中文字符串全部乱码 → 脚本必须**纯 ASCII**，
    中文逻辑放在上传的 bash 脚本里；
  - `Install-Module Posh-SSH` 在非交互模式下失败，且要装到
    `~/Documents/WindowsPowerShell/Modules`（**不是** `~/Documents/PowerShell/Modules`）。
- `Posh-SSH` 的 `New-SSHSession` 需要 `-AcceptKey -Force`；`Invoke-SSHCommand`
  的命令里若含中文/反引号，容易被 PowerShell 的 here-string 吃掉 —— 长命令写成文件再传。

### 头像上传失败（code=6003）—— 根因是 Docker 卷权限

**症状**：线上 `POST /api/v1/upload/avatar` 返回 `code=6003 图片保存失败`。

**根因**：`Dockerfile` 里 `RUN chown -R app:app /app` 执行时 **`/app/uploads` 还不存在**，
而 compose 把命名卷挂到该路径。Docker **首次**挂载命名卷时会用镜像里该路径的属主
初始化卷内容；目录不存在时它**以 root 创建挂载点** → 容器以 `app` 用户运行
→ `Files.createDirectories` 直接 EACCES。

**修法**（两层）：
1. `Dockerfile` 在 `chown` 之前 `mkdir -p /app/uploads/{avatar,chat}`。
2. `FileStorageService` 加 `@PostConstruct` **启动自检**：
   创建目录并探测可写性，失败时**打日志给出修复命令**（只告警不阻断启动 ——
   上传坏了不该让聊天/跑步也起不来）。

> 原来这个错误只报一句「图片保存失败，请重试」，排查要从日志翻到 IOException 堆栈；
> 启动自检把「部署配置错了」和「用户传了坏图」区分开了。

### 🐞 已踩过的坑：注销账号漏清理两张表（免打扰偏好 / 推送令牌）

**症状**：调用 `DELETE /api/v1/user/me` 后，`chat_preference` 与 `device_token`
里仍留着指向该用户 id 的行。

**根因**：`UserServiceImpl.deleteAccount` 用**显式 DELETE**清理子表
（刻意不用外键 `ON DELETE CASCADE`，让「注销会删掉哪些数据」在代码里一目了然），
但新增表时**忘了同步加进去**：
`chat_preference` 是本轮新加的免打扰表；
`device_token` 的 `deleteByUserId` **方法早就写好了却一直没被调用**。

**后果**：`device_token` 漏删最严重 —— 账号已注销，令牌仍指向该用户 id，
推送会继续往**这台已经换人的手机**发通知，属于隐私泄露。
`chat_preference` 漏删则让「注销会把数据删干净」这个合规承诺打折扣。

**修法**：两处都补上，并且**两个方向都要删**
（`chat_preference` 既要删「我设的」`user_id`，也要删「别人对我设的」`friend_id`）。

回归测试：`DeleteAccountCleanupTest`（4 个）。
**已验证测试真的能抓到 bug**：临时把清理调用改回缺失状态后，4 个测试**失败 3 个**
（第 4 个「不误删别人令牌」与修复无关，本就该通过）。

> **教训**：用显式 DELETE 而非外键级联时，「新增一张用户相关的表」这件事
> 必须同时改三处 —— 建表 DDL、注销清理、以及对应的清理测试。
> 漏掉第三处不会立刻报错，只会慢慢积累孤儿数据。

### ⚠️ 部署必须用 tar（zip 会毁掉目录结构）

`Compress-Archive` 在 Windows 上写的是**反斜杠**路径分隔符
（`campus-run-common\src\main\`）。Linux 的 `unzip` 把反斜杠当**文件名字符**
而非目录分隔符，解压出来目录结构是错的；而且它还会丢掉目录的 `x` 位，
并且**只要有任何警告就返回 exit 1**（直接打断 `set -e` 脚本）。

**正确做法**：用 Windows 自带的 `tar.exe`（bsdtar）打包，它写**正斜杠**，
解压语义与 Unix 一致：

```powershell
tar -czf $Tar pom.xml campus-run-common campus-run-server   # 在暂存目录里执行
# 打包后校验：tar -tzf 必须能列出 "campus-run-server/src/" 这样的正斜杠路径
tar -xzf campus-run-src.tar.gz -C /home/ubuntu/campus-run-backend   # 直接解压覆盖
```

⚠️ **删旧的解压目录前必须先修权限**：上一次带坏权限解压出来的目录
（缺 `x` 位，`drw-rw-r--`）会导致 `rm -rf` 报 `Permission denied`，
而 `touch`/`rm` 单个文件却正常 —— 极具误导性。顺序必须是
`chmod -R u+rwX` → `find -type d -exec chmod 755` → 再 `rm -rf`。


## 单设备登录（2026-10-05，迁移 005）

### 背景

在此之前凭据是**纯 JWT**：服务端不留任何记录，同一账号可以在任意多台设备上
同时登录。牵连出的问题（都有代码层证据）：

| # | 问题 | 证据 |
|---|---|---|
| 1 | 第二台设备**顶掉**第一台的 WebSocket | `ConcurrentHashMap<Long, WebSocketSession>` 以 userId 为 key，`put` 直接覆盖 |
| 2 | 改密码不会让旧设备下线 | access token 完全不校验 `tokenInvalidBefore`（只有 refresh 校验），最长 2 小时仍可用 |
| 3 | 已读回执串台 | 已读是全局状态：A 设备读了，B 设备的红点也没了 → B 永远收不到通知 |
| 4 | 手机丢了无法远程下线 | 没有任何服务端会话记录，也没有「退出所有设备」入口 |
| 5 | 两台设备各记一条轨迹 | 无并发保护 |

### 做法

`user` 表加两列：

- `token_version INT NOT NULL DEFAULT 0` —— 递增即让该用户**所有**已签发令牌失效；
- `device_id VARCHAR(64)` —— 最近一次登录的设备标识（客户端生成的随机串，
  不是硬件 ID：只需要「同一安装内稳定」，不需要跨安装识别同一台手机）。

规则：

- 设备标识**相同**（或客户端没上报）→ 不动版本。
  同一台手机重复登录不该把自己踢下线，那是最正常的操作；
- 设备标识**不同** → 版本 +1，旧设备的 access/refresh 立即失效。

客户端收到 `401 + code=4011` 时**不去刷新令牌**（refresh 也是旧版本，刷新必然
失败，白跑一次往返），直接清本地令牌回登录页并提示原因。

### 为什么用版本号而不是复用 tokenInvalidBefore

后者的比较必须放宽成 `isBefore`（JWT 的 `iat` 只有秒级精度，而它带毫秒），
于是「同一秒内签发的旧令牌」会有约 1 秒存活窗口。
单设备登录要求的是**精确**失效。

顺带把 access token 也纳入 `tokenInvalidBefore` 校验 —— 之前只有 refresh 校验，
所以「改密码立即踢下线」对 access token 不生效。

### 缓存 TTL 必须分开（踩到的真坑）

`JwtAuthenticationFilter` 为了不给每个请求都查库而缓存了用户状态。
第一版把**令牌版本和角色一起缓存 60 秒**，结果：

```
设备 A 的请求把版本 1 写进缓存
设备 B 登录 -> 数据库版本升到 2
设备 A 再请求 -> 令牌里是 1，缓存里也是 1 -> 相等 -> 校验通过
=> 第一次换设备踢不掉旧设备，第二次才生效
```

实测就是这样：A→B 时 A 仍能用，B→A 时 B 才被踢。

**修法**：两者分开计时 —— 角色缓存 60 秒（降权慢一点业务上可接受），
**令牌版本缓存 3 秒**（踢下线必须准）。代价是每个请求多一次按主键的轻量查库。

另有一条护栏测试钉住「版本缓存必须显著短于角色缓存」，
把 TTL 改回 60 秒会让测试失败。

### 上线顺序（重要）

**必须先迁移再加代码**，否则新代码一遇到新设备登录就会因为列不存在而 500：

```bash
# 1) 迁移（幂等）
mysql -uroot -p"$DB_PASSWORD" campus_run < docs/migrations/005_single_device_login.sql
# 2) 再部署后端
```

迁移时 27 个已有用户全部落在 `token_version = 0`，而他们手上的旧令牌
没有 `ver` claim、解析时按 0 处理 —— **不会被这次上线强制下线**。

### 另一个坑：MyBatis-Plus 的 lambda wrapper 在纯单测里不可用

`sleep`（原文如此）实现最初用 `LambdaUpdateWrapper`，它需要在 MyBatis 容器里
注册过实体元数据，Mockito 单测直接报
`MybatisPlus can not find lambda cache for this entity`。
改用字符串列名的 `UpdateWrapper` 后单测可跑，代价是列名变成字面量 ——
所以补了一条断言守着「列名与迁移脚本一致」（写错不会编译报错，只会在真机静默失败）。

⚠️ `UpdateWrapper.getSqlSegment()` **只返回 WHERE 部分**，SET 子句要用
`getSqlSet()`（实测踩到：断言一直拿不到 `token_version`）。


## 用户 ID 连续化迁移（006_sequential_ids.sql）

### 目标

| 项 | 规则 |
|---|---|
| 管理员 | id/unique_id = `0`/`00000000`、`1`/`00000001`、`2`/`00000002` |
| 其余用户 | 按注册（原 id）顺序，从 `3`/`00000003` 起递增 |
| 新注册 | `unique_id = LPAD(id, 8, '0')`，即接在当前最大值之后 |
| 生成器 | `UniqueIdGenerator` 从随机改为**取现有最大值 +1** |

### ⚠️ 副作用：所有人被强制下线

JWT 的 subject 存的就是用户 id。**id 一改，旧令牌的 subject 会指向
另一个用户** —— A 的令牌可能变成 B 的身份，B 若是管理员就是提权。

所以迁移里主动把 `token_version + 1`，让全部令牌立即失效。
**上线后所有用户需要重新登录一次**，这是唯一安全的做法。

### ⚠️ 迁移前的安全流程（必须照做）

```bash
# 1) 先跑只读探针，确认重排不会撞任何唯一约束
mysql ... campus_run < docs/migrations/probe_collisions.sql

# 2) 探针全部「无冲突」后，再备份
mysqldump --single-transaction campus_run > backup.sql

# 3) 执行迁移
mysql ... campus_run < docs/migrations/006_sequential_ids.sql

# 4) 核对自检输出：id 连续 / unique_id 一致 / 引用完整性 / 行数核对
```

### 四个踩过的坑（都是真实故障，不要重蹈）

#### 坑 1：带唯一约束的表**不能**用「逐列两条 UPDATE」

`friendship` 有 `UNIQUE (user_id, friend_id)`。想当然写两条 UPDATE：

```sql
UPDATE friendship SET user_id  = <新>;   -- 第一条
UPDATE friendship SET friend_id = <新>;  -- 第二条 ← 必挂
```

**顺序怎么调都躲不掉**。第二条要在「已被第一条改过」的表里再找一次映射，
读到的是**中间态**。

#### 坑 2（最核心）：新旧 id 区间重叠 → 必须**两阶段**（先取负）

`user_stats` 的主键**就是 user_id**。新序号 `0..N-1` 与旧 id `1..31`
**大面积重叠**，于是：

```
旧 user_id:  1  2  3
新 user_id:  0  1  2
更新 user_id=1 的行 → 2   ← 而 user_id=2 的行还在（还没轮到）
更新 user_id=2 的行 → 3   ← 而 user_id=3 的行还在
=> Duplicate entry '3' for key 'user_stats.PRIMARY'
```

**解法的关键洞察**：先把所有值搬到一个**与目标区间完全不重叠**的空间
（负数），再一次性搬到目标。负数天然满足 —— 目标是非负的。

```sql
-- 阶段 1：全部取负（同表的多列必须在同一条 UPDATE 里，否则留下半负半正的中间态）
UPDATE friendship SET user_id = -(user_id + 1), friend_id = -(friend_id + 1);
-- 阶段 2：从负数空间映射到目标
UPDATE friendship f JOIN neg_map m ON f.user_id = m.from_id SET f.user_id = m.to_id;
```

这样中间态永远是负数，任何唯一约束都不会被触发。

#### 坑 3：DDL 隐式提交会让 ROLLBACK 失灵

曾加过一个 `@dry_run` 开关靠 `ROLLBACK` 撤销。它是**失灵**的：
`CREATE` / `DROP` / `RENAME` 属于 DDL，会**隐式提交**事务，
于是 ROLLBACK 只撤销最后一段 DML —— 一旦在那之后出错，
**前面已改的 user 表就留在库里了**（实际发生过，且造成过一次
「user 表已重排、其它表没跟上」的不一致状态）。

改用两阶段后不再需要任何 DDL，问题自然消失。
现在的「干跑」是执行前的 `probe_collisions.sql`（只读、不碰数据）。

#### 坑 4：备份表必须 `DROP + CREATE`，不能 `IF NOT EXISTS`

为了「保留上次备份」改成 `IF NOT EXISTS`，结果第二次执行时 INSERT
又插一遍 —— 同一个 `old_id` 出现两次，`ROW_NUMBER()` 给重复的
`old_id` 分配了不同 `new_id`，映射表里出现**互相矛盾的两组映射**。

另外：`user_stats` **没有 id 列**（主键就是 `user_id`），
备份时写 `SELECT id FROM user_stats` 会直接
`Unknown column 'id' in 'field list'`。

### 探针为什么必不可少

最初的碰撞检测是「按新 user_id 分组看有没有重复」。**它发现不了真正的碰撞**
—— 真正的形态是**交叉碰撞**：A 的新值恰好等于 B 的旧值。

```
旧数据：user 4 有 (weekly, 2026-09-28, 1)
        user 1 有 (weekly, 2026-09-28, 1)
重排后：user 4 → 1
结果：两行都变成 (user_id=1, weekly, 2026-09-28, 1)  ← 撞
```

按新 user_id 分组看，一行来自 user 4、一行来自 user 1，看起来各不相干。
正确做法是把**完整的最终键**算出来再查重复（`probe_collisions.sql` 就是这么写的）。

### 结语

这次迁移连续失败了 5 次才成功，每次都是「跑一半报 Duplicate entry」。
根因不是数据脏，而是**方法错**：逐个表试探、逐个表补。
正确的顺序是**先把终态算出来验证，再动手**。

>`probe_collisions.sql` 与 `006_sequential_ids.sql` 都保留在
>`docs/migrations/` 下，以后再有类似的 id 重排可以直接复用。


## HTTPS 改造：从明文到「加密 + 直连」（2.0.1，2026-10-06）

### 改造前的状态

App 用 `http://122.51.191.145:8080` —— **全程明文**，密码、令牌、
聊天内容都能被网络中间环节读到。

而 HTTPS 一直没做成，此前的结论是「域名证书问题，已放弃」。
实际上**证书从来不是问题**，真正的因果链是：

```
境内服务器 + 域名未备案
      ↓
入站 80/443 被拦截（腾讯云策略）
      ↓
ACME 的 http-01 / tls-alpn-01 都收不到验证请求
      ↓
只能改用 Cloudflare 源站证书（origin.crt）
      ↓
但源站证书**客户端不信任**（它只在 CF → 源站 之间受信）
      ↓
对外只能经 Cloudflare 代理
      ↓
Cloudflare 把国内流量绕到境外节点（实测 LAX / LHR）再回上海
      ↓
每个请求多花 0.8~3.9 秒 → 体验上像是「HTTPS 不可用」
```

关键点：**卡住的是验证方式，不是证书本身**。

### 破解方法：DNS-01

ACME 有三种验证方式，前两种都依赖被封的端口：

| 方式 | 依赖 | 本机可用 |
|---|---|---|
| http-01 | 80 端口可达 | ❌ 被封 |
| tls-alpn-01 | 443 端口可达 | ❌ 被封 |
| **dns-01** | 能改 DNS 的 TXT 记录 | ✅ **唯一可行** |

DNS-01 靠往 `_acme-challenge.<域名>` 加一条 TXT 记录来证明域名所有权，
**完全不碰任何端口**，因此不受备案策略影响。

### 具体做了什么

1. **签发证书**（服务器上执行）
   ```bash
   apt-get install -y certbot python3-certbot-dns-cloudflare
   # 凭据文件（仅 root 可读）
   echo 'dns_cloudflare_api_token = <token>' > /etc/letsencrypt/cloudflare.ini
   chmod 600 /etc/letsencrypt/cloudflare.ini

   certbot certonly --dns-cloudflare \
     --dns-cloudflare-credentials /etc/letsencrypt/cloudflare.ini \
     --dns-cloudflare-propagation-seconds 30 \
     -d api.hibiscus.wiki -d dl.hibiscus.wiki \
     --non-interactive --agree-tos --register-unsafely-without-email
   ```
   ⚠️ Cloudflare token 权限只需 **Zone:DNS:Edit**，且**限定到 `hibiscus.wiki` 一个域名**。

2. **Caddy 增加 `le_tls` 片段**，只让 `api` / `dl` 用它；
   `hibiscus.wiki` 继续用源站证书（那条链路走 Cloudflare，不能动）。

3. **DNS 改为「仅 DNS」（灰云）**：`api` / `dl` 从 Cloudflare 代理改为直连源站。
   用 Cloudflare API 改 `proxied: false` 即可。

4. **`PUBLIC_BASE_URL` 改为 HTTPS**（`.env`），这样 `apkUrl` 也走加密通道。

5. **App 重新构建**，`--dart-define=API_BASE_URL=https://api.hibiscus.wiki:8443`。

### 实测效果

| 线路 | 响应耗时 | 证书 |
|---|---|---|
| 明文 IP:8080（改造前） | 0.064 秒 | — |
| **加密直连（改造后）** | **0.129 秒** | ✅ 受信任 |
| 经 Cloudflare（改造前的 HTTPS） | 0.85~3.9 秒 | ✅ |

阶段拆解（直连 vs 经 CF）：

```
直连:  TCP 31ms + TLS 79ms + 首字节 112ms
经 CF: TCP 240ms + TLS 477ms + 首字节 842ms   ← 全花在跨国往返上
```

代价只有**一次 TLS 握手的 ~65ms**，换来全程加密。

### ⚠️ 3 个必须知道的坑

#### 坑 1：`deploy-site.ps1` 会用本地 Caddyfile 覆盖服务器

我在服务器上改了 Caddyfile 接上 le 证书，然后跑了一次 `deploy-site.ps1` ——
它把**本地仓库里的旧 Caddyfile** 传上去覆盖了，HTTPS 立刻全挂。

**规则：Caddyfile 的改动必须改本地仓库里的 `campus-run-backend/docker/Caddyfile`，
不要只改服务器。** 服务器上的那份是部署产物。

（脚本本身是对的 —— 它会先备份服务器上的旧配置到
`docker/Caddyfile.bak-<时间戳>`，回滚可以从那里取。）

#### 坑 2：`admin off` 导致 `caddy reload` 不可用

Caddyfile 全局有 `admin off`，admin API（:2019）不监听，
因此 `caddy reload` 会报 `connection refused`。**必须重启容器**：

```bash
docker restart campus-run-caddy
```

#### 坑 3：续期**不会自动同步到 Caddy**

certbot 续期只更新 `/etc/letsencrypt/live/...`，而 Caddy 读的是
`certs/le-fullchain.crt`（一份**拷贝**）。

没有同步钩子的话，续期成功但 Caddy 看不到新证书 ——
90 天后突然「HTTPS 全部不可用」，且很难联想到续期。

所以装了 `/etc/letsencrypt/renewal-hooks/deploy/sync-to-caddy.sh`：
续期成功后自动复制证书 → 重启 Caddy → 自检 HTTPS 是否 200 → 写日志。

验证方式（手动跑一次即可确认整条链路）：

```bash
sudo /etc/letsencrypt/renewal-hooks/deploy/sync-to-caddy.sh
sudo tail -10 /var/log/letsencrypt/deploy-hook.log
```

预期输出：

```
[时间] 开始同步证书
[时间] 续期后自检 HTTP 200
[时间] 新证书到期: Jan  4 11:00:12 2027 GMT
[时间] 完成
```

### 保留的兼容性

- **旧的明文地址 `http://122.51.191.145:8080` 继续可用** ——
  2.0.1 之前的版本仍指向它，不会失联。
- Server 容器仍监听 8080（供 Caddy 反代 + 旧客户端直连）。
- `AndroidManifest` 的 `usesCleartextTraffic` **保留**：
  开发时用局域网 HTTP 调试仍需要它。

### 排查工具

`tools/` 下留了几个可复用的脚本：

| 脚本 | 用途 |
|---|---|
| `probe_tls.py` | 探测各域名/端口的 TLS 可用性与证书信任状态 |
| `verify_direct_https.py` | 对比明文 / 直连 / 经 CDN 三条线路的速度 |
| `analyze_latency.py` | 拆解 DNS / TCP / TLS / 首字节各阶段耗时 |
| `set_dns_only.py` | 改 Cloudflare 记录的代理开关（试运行 + `--apply`） |
| `check_pdf_bounds.py` | （文档排版用）从 PDF 真实坐标判断内容是否越界 |
