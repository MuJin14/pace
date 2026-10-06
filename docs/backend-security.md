# 鉴权、限流与后端专题

双令牌鉴权与限流、离线推送、WebSocket 安全、已读回执、目标周期、数据库升级。

## 鉴权与限流（已实现）
**双令牌**，解决「24 小时单令牌导致每天被强制登出」：

| 令牌 | 有效期 | 用途 |
|------|--------|------|
| access | `jwt.expiration`，默认 2 小时 | 随每个请求发送（`Authorization: Bearer`） |
| refresh | `jwt.refresh-expiration`，默认 30 天 | 仅用于 `POST /api/v1/auth/refresh` 换新 access |

- 两类令牌都带 `typ` 声明；**`parseAccessToken` 只接受 access**，因此长效 refresh token 无法直接调业务接口（`JwtAuthenticationFilter` 即用它鉴权）。这是双令牌方案最容易出的漏洞，已有单测固化。
- 前端 `AuthInterceptor` 遇到 401 会自动刷新并**重放原请求**；刷新用**单飞（single-flight）**保证并发 401 只触发一次刷新，并只重放一次防止死循环。刷新失败则清空两类令牌回登录页。
- 登出用 `TokenStorage.clearAll()`（只清 access 会留下可用的 refresh token，等于没登出）。

**入口限流**（`RateLimiter`，进程内滑动窗口，零依赖）：

- `login` / `register` / `refresh` 三个入口，按「手机号 + IP」双维度计数（手机号 10 次 / 5 分钟，IP 30 次 / 5 分钟），超限返回 `429 TOO_MANY_REQUESTS`。
- 只按 IP 挡不住分布式撞库，只按手机号挡不住批量注册刷不同号，两者叠加才有效。
- 真实 IP 由 `ClientIpResolver` 按 `X-Forwarded-For` → `X-Real-IP` → `remoteAddr` 解析。**部署前提**：应用端口不能直接暴露公网，否则客户端可伪造该头绕过限流。
- **单实例局限**：多实例部署时各实例独立计数，实际限额 = 单实例限额 × 实例数；届时应把 `RateLimiter` 换成 Redis 实现（接口不变）。

**配置外部化**：`application.yml` 的数据库与 JWT 密钥全部支持环境变量覆盖
（`DB_URL` / `DB_USERNAME` / `DB_PASSWORD` / `JWT_SECRET` / `JWT_EXPIRATION` / `JWT_REFRESH_EXPIRATION` / `CORS_ALLOWED_ORIGINS`），
文件里保留的只是**本地开发默认值**。生产必须注入 `JWT_SECRET` 并把 `CORS_ALLOWED_ORIGINS` 收紧到真实域名。

## 离线推送（已实现后端，前端待接入 SDK）
**目标**：App 完全关闭时收到好友消息也能在通知栏看到。

- 通道：**FCM HTTP v1**（`POST /v1/projects/{id}/messages:send`）。
  旧版「服务器密钥 + `/fcm/send`」Google 已于 2024 年停用，网上教程多为旧版，勿照抄。
- 令牌登记：`POST /api/v1/device/token`（幂等）；登出须 `DELETE /api/v1/device/token?token=...`。
  `device_token.token` 唯一，注册用 `ON DUPLICATE KEY UPDATE` **改写归属** ——
  同一台设备换账号登录时 FCM 令牌不变，不改写就会把通知推给上一个账号（隐私泄露）。
- `PushSender` 抽象 + 两个实现：`LoggingPushSender`（默认，无凭证时把通知内容写日志）
  与 `FcmPushSender`（`app.push.enabled=true` 时生效）。
  这样**没有 Firebase 凭证也能把整条链路跑通并测试**，凭证另行注入。
- 关键行为（均有单测）：
  1. **对方在线时不推** —— WebSocket 已经显示了，再弹系统通知是重复打扰；只有 `!isOnline` 才推。
  2. **先落库再推** —— 推送失败绝不丢消息。
  3. **令牌失效（UNREGISTERED）才删令牌**；临时故障（429/5xx/网络）保留令牌，删错会让用户永远收不到通知。
  4. 推送任何异常都吞掉，不影响消息发送。
  5. 通知正文按**码点**截断（60 个 emoji 不会切出半个）。
- 配置：`app.push.enabled` / `app.push.credentials`（服务账号 JSON 路径，支持 `classpath:` 与绝对路径）。
  **凭证含私钥，必须在 .gitignore 中排除**；`google-services.json` / `GoogleService-Info.plist`
  则**不要**排除（会被打包进 App，本就不算机密，排除会导致别人无法构建）。
- 完整配置步骤（Firebase 建项目、Android/iOS/Web 三端设置、验证与排错）见
  `campus-run-backend/docs/push-setup.md`。
- **待办**：前端尚未接入 `firebase_core` / `firebase_messaging` 与后端登记调用；
  真机验证需要真实凭证，当前仅在 `LoggingPushSender` 下验证过链路。

## WebSocket 安全备注
- WebSocket 握手鉴权：JWT 通过 URL query 参数 `?token=<jwt>` 传递（浏览器/Flutter WebSocket 无法自定义 Header）；`/ws/**` 在 Spring Security 中放行，鉴权由 `AuthHandshakeInterceptor` 完成，未登录连接会被拒绝。
- 生产环境需在 Nginx 层关闭 `/ws` 路径的 query 参数日志（避免 token 泄入 access log），或改用 `Sec-WebSocket-Protocol` 头传递 token。
- 服务端→客户端消息类型：`message` / `ack` / `read_receipt` / `pong` / `error`（详见 `docs/api.md` 的 WebSocket 章节）。

## 消息已读回执（已实现）
- `ChatMessageResponse.readAt`（Long 毫秒时间戳，`null` = 未读）。
- 拉取 `GET /api/v1/message/history` 时隐式把「好友发给我且未读」的消息标记已读。
- 显式接口：`POST /api/v1/message/read?messageIds=1&messageIds=2`（整批校验权限，非本人接收的消息返回 403，幂等）。
- 标记成功后向发送方推送 WebSocket `read_receipt`：`data = { readerId, friendId, messageIds, readAt }`。
  （详见 `campus-run-backend/docs/api.md` 第 16 / 16.1 节与 WebSocket 消息类型表。）

## 运动目标周期（已实现）
- `POST /api/v1/goals` 只需 `periodType` + `targetDistanceMeters`。
- `weekly` = 服务端按 `Asia/Shanghai` 推导为本周一~周日；`monthly` = 当月 1 日~月末；客户端传的 `startDate`/`endDate` 被忽略。
- `custom` 必须传 `startDate` 与 `endDate`，缺失或 `endDate < startDate` 返回 400。（详见 `docs/api.md` 第 22 节。）

## 上传与媒体存储（两道防护）

上传接口是**外部唯一能往服务器写数据的地方**。写满磁盘的后果不是「图片坏了」，
而是 **MySQL 一起挂掉 —— 整个 App 下线**（登录、跑步记录、聊天全部报错）。

### 防护一：磁盘余量守卫（`StorageGuard`）

上传前用 `FileStore.getUsableSpace()` 探测真实剩余空间，低于
`app-storage.min-free-mb`（默认 **512MB**）就拒绝上传。

- 用**文件系统剩余空间**而不是「累加 uploads 目录大小」：后者是 O(n) 遍历，
  而且只统计 uploads 会严重高估可用空间（磁盘上还有 Docker 镜像、日志、MySQL 数据文件）；
- 探测失败时**放行**：宁可让一次上传成功，也不要因为探测异常把整条链路打死；
- 只拒绝**上传**，不影响已有数据和其它接口。

现状参考：单张上限 2MB，客户端已压缩到 200-500KB，
所以 38GB 可用空间需要约 19000 张才会撑满 —— 正常永远碰不到。

### 防护二：聊天图片保留策略（`MediaRetentionService`）

每天 04:10 清理超过 `app-media.retention-days`（默认 **90 天**）的聊天图片。
选 04:10 而不是 03:00：错开排行榜/目标的定时任务，避免同时抢数据库连接。

**三条设计约束**（都有测试固化）：

1. **删文件，但保留消息** —— 后端把 `message.media_url` 置空。
   直接删消息行会让聊天记录凭空少几条，用户会以为丢数据。
   前端据此显示「图片已过期」（`_emptyMediaLabel()`，按消息时间判断）。
2. **仍被引用的文件绝不删** —— 先查出所有非空 `media_url`，再删不在其中的文件。
   按**文件名**比对而不是完整 URL，这样历史域名变化（IP → HTTPS 域名）不会误判。
3. **先改库、再删盘** —— 顺序反过来的话，删文件成功但改库失败会让消息指向
   不存在的文件（表现为「图片加载失败」）；现在最坏只是文件多留一天。

**头像是独立目录，不在清理范围内** —— 用户头像过期会很奇怪，
而且头像是单文件覆盖，不会无限增长。

### 为什么默认 90 天而不是 7 天

7 天太激进：用户翻一周前的聊天时图片全变占位符，观感上像 App 坏了；
而体积上完全没必要（实测整个 uploads 目录才 1.2MB）。
真要更激进就改 `MEDIA_RETENTION_DAYS` 环境变量，`0` 或负数 = 不清理。

## 数据库升级注意事项
- `message` 表已新增按接收方查询未读的索引，**生产库需手工执行一次**（`schema.sql` 已包含；执行前先确认索引不存在，避免重复添加报错）：

  ```sql
  ALTER TABLE message ADD KEY idx_receiver_sender_read (receiver_id, sender_id, read_at);
  ```


## 未读红点：从「纯内存态」改为「服务端可重建」（2026-10-05）

### 现象

用户反馈：「等设备下线后给它发消息，等登录时居然没有后面的红点提醒」。

### 根因

客户端的未读红点原本是**纯内存态**，代码注释里写得很清楚：

```dart
/// 未读数的来源有两条：WebSocket 实时到达的消息（markMessage），
/// 以及进入会话后的清空（clearFriend）。
/// 服务端没有「未读计数」接口，所以这里是**内存态**。
```

于是这条链路必然丢红点：

```
设备被顶下线 / 离线  →  期间的消息根本不会到达客户端
用户重新登录        →  红点是空的，看起来「没人找过我」
```

> 注意这是**独立于 WebSocket 的第二个缺口**：即使 WebSocket 修好了
> （后台不再断开），「被顶下线期间」和「App 被系统杀掉期间」收到的消息
> 仍然到不了客户端。任何依赖「实时到达」的计数都补不上历史。

### 修法

**服务端**：新增 `GET /api/v1/message/unread`，一次 GROUP BY 返回
`friendId -> 未读数`（不是按好友逐个查 —— 几十个好友时会有明显延迟）：

```sql
SELECT sender_id AS senderId, COUNT(*) AS cnt
FROM message
WHERE receiver_id = #{receiverId} AND read_at IS NULL
GROUP BY sender_id
```

读状态用 `read_at IS NULL` 判断而不是布尔字段：这样「读过的时刻」
本身也是数据，将来做已读回执不用再加列。

**客户端**：`unreadSyncProvider` 在**两个**时机拉取并重建红点：

- **登录后**（userId 从 null 变为非 null）—— 覆盖离线期间积压的消息；
- **每次回到前台** —— 覆盖「App 在后台被系统冻结、WebSocket 收不到」的时段。

只做登录后同步是不够的：用户切回 App 时仍然看不到红点。

**合并策略取较大值**而不是直接覆盖：服务端的未读在「消息落库」时确定，
而本地计数可能已包含刚通过 WebSocket 到达、服务端统计尚未反映的那一条；
直接覆盖会让用户刚看到的红点又消失。

### 测试

- 后端 `MessageUnreadCountsTest`：行转换、只查一次库、过滤 0 与脏行、null 用户；
- 端到端实测：直接造 3 条未读消息 → 登录后调接口返回 `{"32": 3}` ✅；
- 清理：诊断用户与其消息已删除，线上用户数回到 27。


## 未读红点的第二轮修复（2026-10-05）

第一轮只解决了「离线消息登录后没有红点」。用户随后反馈三个新问题，
每一个都是独立缺陷：

### ① 切到「社区」Tab 会清空全部红点

```dart
// main_shell.dart 的「社区」Tab onTap
ref.read(friendBadgeProvider.notifier).clearMessage();   // ← 清空全部未读
navigationShell.goBranch(2, ...);
```

原意大概是「进社区就算看过了」。但红点的语义是**「这条消息你还没读」**，
而切到社区只是看到好友列表，没有读任何一条消息 ——
用户切走再回来发现红点全没了，明明还没点进去看过。

**修法**：删掉那行。清除时机只剩两个，都是用户**明确表达已读**的动作：
真正进入某个会话（`chat_page` 的 `clearFriend`）、
或在通知页点「全部已读」。

### ② 离线消息登录后很久才出现红点

第一版的同步触发器写在常驻 Notifier 的 `build()` 里用
`ref.listen(authProvider)`，还加了 600ms 延迟避让首屏请求 ——
登录事件到同步请求之间隔着好几层异步，时序不确定。

**修法**：改成 provider **直接依赖 userId**：

```dart
final userUnreadSyncProvider = FutureProvider.family<void, int>((ref, userId) async {
  final counts = await ref.read(messageRepositoryProvider).unreadCounts();
  ...
});
```

「登录」于是只是一次普通的依赖变化，Riverpod 立刻重建、同步随即发出，
没有额外监听链路，也不需要猜延迟。

### ③ 通知看不出是谁发的

`ChatMessageResponse` 里**只有 `senderId`、没有昵称**。客户端只能去查
好友列表，而那个列表要等用户进过社区页才加载 —— 冷启动后收到的第一条消息，
通知标题只能是「新消息」。

**修法**：服务端在消息里直接带 `senderNickname`。
发送者信息在服务端本来就有，且不受客户端缓存状态影响。

实测（裸 WebSocket 客户端走一遍真实链路）：

```json
{"type":"message","data":{"messageId":53,"senderId":38,
 "senderNickname":"推送甲","receiverId":39,"content":"验证昵称",...}}
```

### 顺带修掉的两个隐患

- **`ChatMessage.copyWith` 漏传 `senderNickname`**：发送中 → 已送达
  正好走 `copyWith`，昵称会被静默丢掉，通知标题随之退化成「新消息」。
  这类字段漏传不会编译报错。
- **「拉取失败」与「确实没有未读」分不清**：仓库层原本失败也返回空 Map，
  一次网络抖动就会把用户已有的红点全部清掉。
  改成返回**可空**类型：成功给 Map（可能为空），失败给 null，调用方跳过。

### 未读接口改为返回完整快照

`GET /api/v1/message/unread` 现在返回**所有好友**（未读为 0 也给 0），
而不是只返回有未读的。否则客户端无法区分
「这个好友没有未读了」和「这次请求没查到这个好友」，
本地红点永远清不掉 —— 会积累出**僵尸红点**。

用一次 `FriendshipMapper.selectAcceptedFriendIds` + 一次 GROUP BY 拼出来，
不额外查库。


## 长连接保活：退到后台也能收到消息（2026-10-05）

### 问题

消息走 WebSocket，**需要进程活着才能收到**。App 退到后台后，Android 的
Doze / 省电策略会**冻结本进程的网络**，WebSocket 被掐断，
期间的消息全部丢失 —— 用户表现为「App 放到后台就收不到消息」。

> 注意这与「切 Tab 清红点」「离线消息无红点」是两个不同的问题：
> 那两个是**状态管理**缺陷，这个是**进程存活**问题。

### 方案：前台服务

前台服务是 Android 提供的**唯一合法**的长时运行机制。声明之后系统不会
冻结本进程的网络，WebSocket 得以存活。

**代价（无法绕过）**：前台服务**必须**显示一条常驻通知。
原生侧做成了最低优先级、不响不震不亮屏的静默通知。

### Android 14 的服务类型要求

API 34 起前台服务必须声明类型，否则启动即抛异常。可选类型里：

- `dataSync`：官方语义是上传/下载，不是长连接；
- `connectedDevice`：用于与外设通信，不对；
- **`specialUse`**：为「不属于其他类别的合法用途」准备，
  需要一段 `<property>` 说明理由。

编译产物实测（`aapt2 dump xmltree`）：

```
A: android:name="android.permission.FOREGROUND_SERVICE_SPECIAL_USE"
A: android:name="android.permission.REQUEST_IGNORE_BATTERY_OPTIMIZATIONS"
E: service
  A: android:name="com.example.campus_run_app.KeepAliveService"
  A: android:foregroundServiceType=0x40000000        ← specialUse
  A: android:name="android.app.PROPERTY_SPECIAL_USE_FGS_SUBTYPE"
```

（另一个 service 的 `0x00000008` 是 location，给跑步定位用的，未受影响。）

### 光有前台服务不够：电池优化白名单

国产 ROM（MIUI / EMUI 等）有自家的省电策略，会在息屏一段时间后把
「受限制」的应用冻结，**前台服务照样被杀**。

所以新增「我的 → 后台消息提醒」一页，做两件事：

1. **一键申请「忽略电池优化」**（`ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`
   系统对话框，用户必须手动同意，应用无法静默获得）；
2. **按机型列出各 ROM 的手动设置路径**（MIUI / EMUI / ColorOS / OriginOS）——
   那些没有标准 API 可调，只能写清楚让用户自己去点。

### 为什么保活绑「登录态」而不是「App 生命周期」

消息只对已登录用户有意义：

- 未登录时起一个常驻前台服务，只会白占通知栏一行、多耗一点电；
- **登出时必须停掉**，否则用户以为已经退出了，通知栏却还挂着
  「保持连接中」—— 那是在告诉用户「你还在线」。

绑在「userId 是否非空」这一个判据上，登录/登出/被顶下线/注销账号
所有路径自动覆盖（逐个在登录登出代码里加调用一定会漏）。

### 诚实的局限

这套方案**不是 100% 可靠**：

- 用户在最近任务里**划掉** App，或在设置里「强行停止」→ 服务被杀；
- 部分 ROM 的「严格」省电策略下，前台服务也会被限制。

真正「App 被杀也能收到」只有**厂商系统推送**能做到（小米推送等），
那是另一套接入（需开发者认证、配置 APK 签名指纹、接各家 SDK）。
当前方案的目标是把可达率从「几乎收不到」提升到「大部分情况下能收到」。

### 实现位置

| 层 | 文件 |
|---|---|
| 原生服务 | `android/app/src/main/kotlin/.../KeepAliveService.kt` |
| 原生桥 | `android/app/src/main/kotlin/.../MainActivity.kt`（MethodChannel） |
| Dart 桥 | `lib/core/platform/keep_alive_service.dart` |
| 启停挂钩 | `lib/features/settings/providers/keep_alive_provider.dart` |
| 设置页 | `lib/features/settings/pages/background_message_page.dart` |


## 放弃「前台服务保活」——一次产品取舍（2026-10-05）

上线 1.9.0 的前台服务保活后，用户明确反馈：

> 「回退吧，我不想要这种强制性的，宁可优化其它方面」

**已回退。** 这里记录为什么，避免以后有人再提同一方案时重复讨论。

### 被放弃的方案

App 起一个常驻前台服务维持 WebSocket，让退到后台也能及时收到消息。
技术上可行、能编译能运行，**成本也不高**（¥0、无需账号或审核）。

### 放弃的真正原因

前台服务**必须**在通知栏常驻一条通知 —— 这是 Android 的硬性要求，
**无法绕过**（不是实现问题，是系统设计）。

于是问题变成：

> 为了「消息提醒的及时性」，值不值得长期占用用户通知栏的一行？

对一个**校园跑步 App** 来说，答案是不值得。用户对「装个跑步软件，
通知栏却一直挂着一条通知」的容忍度很低，这属于**强制打扰**。

### 回退后的现状

- 退到后台时**消息仍然收不到即时提醒**（系统会冻结后台应用的网络）；
- 但**消息不会丢**：服务端有未读计数，重新打开 App 时会拉取并重建红点
  （见 `unread_sync_provider`）。所以丢的是**提醒**，不是**消息**。

这个区分很关键 —— 用户真正担心的「会不会漏消息」，答案是不会。

### 保留的部分：只读的机型引导页

「我的 → 后台消息提醒」这一页**保留**，但改成了**纯说明 + 自愿设置**：

- 页面顶部先澄清「**消息不会丢**」（用户最关心的）；
- 只显示电池优化状态 + 各 ROM 的手动设置路径；
- 提供「打开系统电池优化设置」按钮（**只跳转，不申请、不改任何东西**）；
- 文案明确写「完全自愿 —— 不设也不影响任何功能」。

对国产 ROM（MIUI / EMUI / ColorOS / OriginOS 等）来说，**系统级的省电
白名单是唯一有效且不打扰用户的手段**：设不设由用户自己决定。
各 ROM 路径都不一样且藏得很深，把路径写清楚本身就是有价值的工作。

### 教训

**技术上可行 ≠ 产品上可接受。** 这个方案的每一项技术指标都达标
（免费、可靠、可编译），唯一的代价是「通知栏常驻一条通知」——
而这个代价恰好落在用户最敏感的地方。

以后遇到类似取舍，应该**先把代价摆出来问用户**，
而不是做完再回退。
