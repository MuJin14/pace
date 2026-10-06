# 各轮功能优化记录（按轮次归档）

> 这是历史记录，**追加**为主。新的一轮加在最上面。
> 每条都说明「为什么这么做」，避免后人以为是随手写的。

## 第二轮功能优化（进行中）
计划全文见 [`plan-round2.md`](plan-round2.md)。范围：聊天提醒/免打扰、
消息按 5 分钟分组、富媒体消息、运动记录为 0 的 bug、修改密码、性别年龄及可见性。


**数据库迁移 002**（`campus-run-backend/docs/migrations/002_profile_privacy_and_media.sql`）
已在本地 MySQL 实测**三次**（验证幂等）：

| 变更 | 说明 |
|---|---|
| `user.gender` / `age` | 可空；`NULL` = 未填写 |
| `user.gender_public` / `age_public` | `TINYINT NOT NULL DEFAULT 0` —— **隐私默认关闭，公开必须用户主动开启** |
| `user.token_invalid_before` | 改密后写入；**早于该时间签发的 refresh token 一律拒绝** |
| `message.media_url` | `type=2`（图片）时必填 |
| `message.content` | 改为**可空** —— 图片/表情消息可以没有文字 |
| `chat_preference` 表 | 会话级免打扰，`UNIQUE(user_id, friend_id)` |

写法约定：迁移用 `PREPARE` + `information_schema` 判断列是否存在来保证幂等。
**`PREPARE` 串里只放最简单的 `SELECT 1`** —— 一旦在里面写带引号的中文提示，
引号嵌套会让 MySQL 报 1064（已踩过）。

⚠️ 同步维护三处 schema，漏一处会导致测试或新装库缺列：
`docs/schema.sql`（新装生产库）、`campus-run-server/src/test/resources/schema.sql`（H2 测试）、
`docs/migrations/*.sql`（既有库升级）。


**症状**：App 勋章墙显示 `Ã¥Ë†ÂÃ¨Â·â10Ã¥âÂ¬Ã©âÂ¡Å` 这类乱码，而 `docs/schema.sql`
文件本身是**干净的 UTF-8**（用字节验证：`校` = `E6 A0 A1`）。

**成因**：只设了 `--character-set-server=utf8mb4`，**没设客户端连接字符集**。
MySQL 的 `docker-entrypoint-initdb.d` 在执行 `schema.sql` 时用的是**连接字符集**，
未指定时退回 **latin1** → UTF-8 的中文字节被当作 latin1 字符再编码成 utf8mb4 →
每个汉字变成 2-3 个乱码字符（双重编码）。

**修法（两层都要做）**：
1. **防复发**：`docker-compose.deploy.yml` 的 mysql `command` 必须同时带
   `--character-set-client=utf8mb4`、`--character-set-connection=utf8mb4`、
   `--character-set-results=utf8mb4`。
2. **修存量**：`docs/migrations/003_fix_badge_mojibake.sql` —— 用**权威文案覆盖**
   而不是反向 `REPLACE`（双重编码有多种变体，反向替换容易漏），并清理
   `user_badge` 里引用不存在 badge 的孤儿行（表现为接口返回 `name=null`）。

**为什么一开始是好的、后来又坏了**：数据卷 `mysql-data` 只在**首次创建时**执行
initdb 脚本。重建容器不会重跑；但一旦数据卷被删（或换新库）就会按当时的 compose 配置
重新初始化 —— 所以这个 bug 会在"看起来什么都没改"的时候突然出现。

**排查要点**：不要只看 `SELECT name FROM badge`（终端编码会二次误导），
用 `SELECT id, HEX(name) FROM badge` 看真实字节，或从 API 取 JSON 后用 Python 打印。


| 接口 | 说明 |
|---|---|
| `PUT /api/v1/user/password` | 修改密码；成功后写 `token_invalid_before`，旧 refresh token 全部失效 |
| `POST /api/v1/upload/chat-image` | 上传聊天图片（与头像共用同一套安全校验，落 `uploads/chat/`） |
| `GET /api/v1/chat/preference/muted` | 静音名单 |
| `PUT /api/v1/chat/preference?friendId=&muted=` | 设置/取消免打扰（幂等） |
| `PUT /api/v1/user/me` | 扩展 `gender` / `age` / `genderPublic` / `agePublic` |
| `GET /api/v1/user/{id}/profile` | 性别/年龄按可见性返回；不公开时字段为 `null` |

**消息类型**（`MessageType` 枚举，服务端强制）：

- `1`=文本：`content` 非空，`mediaUrl` 被**丢弃**（防止「文本+图」绕过媒体必填校验）
- `2`=图片 / `3`=表情包：`mediaUrl` 必填，`content` 可空
- **`type` 缺省按文本处理** —— 这是旧客户端兼容项，若把 `null` 当未知类型拒绝，
  老版本 App 会**完全发不出消息**（这个 bug 被单测抓到过）
- 离线推送正文：图片 `[图片]`、表情 `[表情]`（不能让通知栏空白）

**免打扰的三条语义边界**（`ChatMutePushWiringTest` 固化）：

1. 只拦「推送通知」，**不拦消息** —— 照常落库、照常在线送达
2. 方向是「**接收方**静音**发送方**」，不是反过来
3. 对方在线时本来就不推，免打扰判断不改变这一点

后端测试：**303 个用例全绿**（282 基线 + 7 改密 + 8 富媒体 + 6 免打扰）。


| 类型 | `type` | 发送方式 | 渲染 |
|---|---|---|---|
| 文本 | 1 | 输入框 / emoji 面板 | 文字气泡 |
| 图片 | 2 | 输入栏「+」→ 相册 → 上传 | 缩略图（最大 220，可点开） |
| 表情包 | 3 | 表情面板「表情包」页签 | 小图（最大 120） |

**关键实现要点**：

- **图片分两步：先上传、再发消息**。上传失败时**不产生任何消息**，
  比先插一条永远加载不出来的图片消息好得多。
- **emoji 走文本消息**（它们是 Unicode 字符），**只有贴图才走 `type=3`**。
  为每个 emoji 单独存一张图是浪费。
- **`mediaUrl` 用 `asset:` 前缀**区分内置贴图与网络图片：
  `asset:` → `Image.asset`，其它 → `Image.network`。
- **贴图列表为空时自动隐藏「表情包」页签**，而不是显示一堆加载失败的破图。
  项目当前**未附带贴图文件** —— 要启用只需把 PNG 放进 `assets/stickers/`、
  在 pubspec 声明、并填入 `emoji_catalog.dart` 的 `stickerAssets`，**无需改 UI 代码**。
- **媒体消息的 `content` 可以是空串**：模型把 `null` 兜底成 `''`，
  否则服务端返回的图片消息会让**整个会话加载失败**（不是少显示一个字，是打不开）。
- ⚠️ **重试必须带上原 `type` / `mediaUrl`**：漏了会把图片重试成一条**空的文本消息**
  （content 本来就是 `''`），用户看到「重试成功」但对方收到空白 —— 比失败更糟。
  这个 bug 我在实现时真实写出来过，已修并有测试固化。
- 媒体地址缺失（脏数据）时显示明确的 `[图片]` / `[表情]` 占位，不留白块；
  加载失败显示「图片加载失败」占位，不用留一个空白气泡。

前端测试：**297 个用例全绿**（19 → 20 个文件）。


项目路径含中文（`C:\Users\沐瑾\...`），**从真实路径构建会失败**：

```
Execution failed for task ':app:compileFlutterBuildRelease'.
> Cannot invoke "java.io.File.exists()" because "parent" is null
Dart snapshot generator failed with exit code 255
Could not write file to ...\build\...\ink_sparkle.frag
```

**正确做法**：用 `subst` 映射盘，且**必须在同一条命令里先建映射再构建**
（`subst` 只在创建它的会话有效，新开的 pwsh 进程里 P: 不存在 —— 我因此白跑了两轮）：

```powershell
& subst P: /D 2>&1 | Out-Null
& subst P: 'C:\Users\沐瑾\Desktop\project\campus-run-app' 2>&1 | Out-Null
Set-Location 'P:\'
flutter build apk --release --dart-define=API_BASE_URL=http://122.51.191.145:8080
```

> `C:\crun` 是指向 project 根目录的 junction，但 **junction 会被解析回真实中文路径**，
> 不能解决这个问题；只有 `subst` 映射盘有效。


| 组件 | 位置 |
|---|---|
| 决策规则（纯函数） | `lib/features/friends/utils/notify_policy.dart` |
| 通知 + 震动封装 | `lib/features/friends/services/chat_notification_service.dart` |
| 接入点 | `lib/app.dart` 的 `_handleIncomingMessage` |
| 权限申请 | 进入聊天页时（不是启动时） |

**决策优先级**（`decideNotifyAction`，17 个测试固化）：

1. **自己发的消息 → 不提醒**（多端登录时会同步回来，给自己弹通知是明显错误）
2. **未登录 → 不提醒**
3. **正在看该会话 → 不提醒**（消息已在眼前）
4. **该会话免打扰 → 只加红点，不震动不通知**
5. 其余 → 震动 + 系统通知 + 红点

**关键实现要点**：

- **Android 必须开脱糖**：`isCoreLibraryDesugaringEnabled = true` +
  `coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")`，
  否则构建直接失败（`flutter_local_notifications` 依赖 Java 8+ API）。
- **Manifest 需 `VIBRATE` 与 `POST_NOTIFICATIONS`**：缺 `VIBRATE` 时部分 ROM
  会「有通知但不震动」，很难排查。
- **通知插件调用全部 swallow 异常**：通知是锦上添花，绝不能影响消息接收与红点。
- **媒体消息的通知正文用占位**（`[图片]` / `[表情]` / `[消息]`），
  否则通知栏会出现一条**空白通知**。
- 通知 id 用**发送方 id**：同一好友的多条消息覆盖同一条通知，不堆满通知栏。


**服务器 `122.51.191.145:8080` 已运行本轮全部改动**，并已完成迁移 002 + 003。

已实测通过的线上接口：

| 验证项 | 结果 |
|---|---|
| 登录 | `code=0`，userId=1 |
| `GET /user/me` | 返回 `gender:null, age:null, genderPublic:false, agePublic:false`（隐私默认关闭 ✅） |
| `GET /user/{id}/profile` | 返回 `gender/age` + `relation` |
| `GET /chat/preference/muted` | `data: []` |
| `GET /user/{id}/badges` | `初跑10公里` / `十次运动` —— **乱码已修复** ✅ |
| `GET /leaderboard` | 中文昵称正常、`relation` 正常、`gapToAhead/Behind` 正常 |
| `POST /upload/chat-image`、`PUT /user/password`、`PUT /chat/preference` | 均已注册（非 404） |
| `POST /admin/maintenance/repair-distance?dryRun=true` | `HTTP 200`，`scannedZeroDistance: 0` |

> 服务器上**没有**「距离为 0」的历史记录，所以历史修复实际上无事可做
> （接口已就绪，将来若出现可直接调用）。


- 真机装 APK 验收（`C:\Users\沐瑾\Desktop\campus-run.apk`）
- **强烈建议改服务器密码**：当前密码是 `123456`，极弱；
  服务器 22 端口对公网开放，存在被暴力破解风险（本轮已实测：SSH 密码认证可用，
  说明**没有**禁止密码登录、也没有 fail2ban）。
- 历史坏数据修复：服务器上无此类记录，无需执行。

## 第三轮功能优化（进行中）

**管理员后台（找回密码）** —— `docs/migrations/004_admin_and_password_reset.sql`

背景：App **没有邮箱字段、也没有短信服务**，用户忘记密码后毫无自救途径。
硬上短信要实名 + 备案 + 按条付费，代价远大于收益。因此改为
**给少量受信任账号开管理员权限**（`user.role = 1`），由管理员协助重置。

| 接口 | 说明 |
|---|---|
| `GET /api/v1/admin/users` | 分页查用户，可按手机号 / 昵称 / 专属 ID 搜 |
| `POST /api/v1/admin/users/{id}/reset-password` | 直接重置，返回**一次性**临时密码 |
| `GET /api/v1/admin/password-reset-requests` | 申请列表（`status=0` 只看待处理） |
| `POST /api/v1/admin/password-reset-requests/{id}/resolve` | 处理并重置 |
| `POST /api/v1/admin/password-reset-requests/{id}/reject` | 拒绝 |
| `POST /api/v1/password-reset-requests` | **用户侧提交申请（免登录）** |
| `GET /api/v1/password-reset-requests/mine` | 查看自己最近一次申请状态 |

**安全边界**（14 个测试固化，重点不是「能用」而是「不能越界」）：

- 管理员**不能**通过这条路径重置自己的密码 —— 否则等于给管理员账号一个
  「无需旧密码改自己密码」的后门，access token 一泄漏就能夺号。
  错误信息会引导他去用「修改密码」。
- 重置会写 `token_invalid_before`，**作废该用户全部 refresh token**
  （与改密同一套机制；不写的话 30 天有效的旧 refresh token 仍能换新 access）。
- 临时密码用 `SecureRandom` 生成，**字符集刻意去掉易混字符**（0/O、1/l/I）——
  它是靠口头或文字转达的，「0 还是 O」会让用户反复输错、又来一轮重置。
- **提交申请时，未注册手机号也返回成功**：否则这个免登录接口就成了
  「哪些号注册过本 App」的批量探测器。
- 同一用户只保留一条待处理申请，避免管理后台被同一个人刷屏。
- 管理后台的用户列表**没有密码字段**（有测试用反射兜底，防止将来被「顺手」加上）。
- 提交申请是 `POST` **精确路径**放行，不是 `/api/v1/password-reset-requests/**` ——
  否则连 `/mine` 也变成匿名可访问。

**前端**

- `/forgot-password` —— 登录页密码框下方有「忘记密码？」入口。
  **路由守卫必须放行它**（未登录 + 网络异常两种状态都要放行）：忘记密码的人本来就登不上，
  守卫把人挡回登录页等于让他回到原点。已加入 `resolveRedirect` 的 `escapable` 集合。
- `/admin` —— 两个页签：「找回密码申请」（有人等我）/「用户查询」（我要找某人）。
  刻意分开：混在一页会让「还有几个人在等」被搜索框淹没。
- 「我的」页 → 「忘记密码怎么办」；管理员额外看到「管理后台」入口。


原来的 `FriendBadgeState` 只有一个 `hasUnreadMessage`，界面只能显示「有未读」——
用户回到社区页**不知道该点谁**，必须挨个点开。

现在存 `Map<int, int> unreadByFriend`（好友 id → 未读数），社区页每一行：

- 头像右上角**小红点**（带白边，深色头像上也看得清）
- 右侧**数字角标**（>99 显示 `99+`）
- 副标题从 `ID xxx` 换成「**N 条新消息**」并高亮

两套强度是刻意的：小圆点负责「一眼看到哪行」，数字负责「积了多少」。

用 `select` 只订阅自己那一项，避免别人来消息时整张列表重建。

**打开会话即清红点**：`chat_page` 进入时 `clearFriend(friendId)`；
`app.dart` 在「正在看该会话」分支也清一次（否则读完消息回到列表仍有红点）。


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


**绕不开的技术事实**：Android 8.0 起**禁止应用静默自安装**，任何方案都必须
下载后弹系统安装器让用户点「安装」，首次还要授权「安装未知应用」。
微信、淘宝也是这个流程。国内无法用 Google Play，而华为/小米/OPPO 各自一套 SDK，
所以选**自建更新**（托管 APK + 版本接口）。

| 接口 | 说明 |
|---|---|
| `GET /api/v1/app/version` | 版本信息（**免登录**，`/api/v1/app/**` 已放行） |
| `GET /api/v1/app/download` | 下载 APK（流式 `FileSystemResource`，不读进内存） |

配置（`application.yml` 顶层 `app-version:`，全部支持环境变量覆盖）：
`latest` / `min-supported` / `changelog` / `apk-path`。
**`latest` 留空 = 不提示更新**（接口仍可用）。

关键设计：

- 返回体里有 `apkReady`：**版本号有了但 APK 还没放好时，客户端不该提示** ——
  否则用户点了下载拿到 404，体验比不提示更糟。
- 下载用 `FileSystemResource` 而不是读进 `byte[]`：52MB 在 2C2G 服务器上
  会造成明显 GC 压力，并发下载内存还会翻倍。
- 未配置时返回 **404 而不是 500**：「没有可下载的包」对客户端等同于「暂时没有更新」。
- 前端 `isVersionNewer()` 是**纯函数**（18 个测试）：这段逻辑错了会导致
  「永远提示更新」或「永远不提示」，而这两种都要发两个版本才能在真机上验证一次。
  边界情况包括：段数不同（`1.1` == `1.1.0`）、**多位数字按数值而非字典序**
  （`1.10.0 > 1.9.0`，字典序会判反）、`1.0.0+3` 这类 build 后缀、空串。


用 `Select-String` 取行号再 `$lines[0..($idx.LineNumber-2)]` 插入配置段，
**`Select-String` 返回的不是字符串**（是 `MatchInfo` 集合），
`.LineNumber` 取不到值 → 切片退化 → **文件被截掉大半**。

**教训**：
- 改 YAML/配置文件**不要用行号切片**，用精确字符串替换；
- **不要用 PowerShell 做多行文本编辑**，用 Python（本项目 `tools/` 下有先例）；
- 出事后的救命稻草是 **`target/classes/`** —— 那里有上次编译输出的完整副本。
  这次就是靠它恢复的（而且它比 git 里的版本更新）。
- 插入锚点要按**真实缩进**写：本项目 `application.yml` 的顶层 key（`logging:` 等）
  **没有缩进**，找 `'  logging:'` 会静默失败。


- **部署**：迁移 004 + 新后端（头像修复、管理员后台、版本接口）
- **自更新前端**：APK 下载进度 + 拉起系统安装器的 UI
- 上传 APK 到服务器并设 `APP_VERSION_LATEST`（否则 `latest` 为空，客户端不提示更新）
- 给定账号开管理员：`UPDATE user SET role = 1 WHERE phone IN (...)`

后端（与 `campus-run-backend/README.md` 保持一致）：

- 单端在线：多端同时登录的会话同步未实现。
- **消息已支持富媒体**（`type` 1=文本 2=图片 3=表情包），前后端均已打通，
  见上方「第二轮功能优化 → 富媒体消息」。
- **内置贴图文件尚未附带**：`assets/stickers/` 为空，
  表情面板会自动隐藏「表情包」页签（emoji 不受影响）。
- 管理员暂无前端管理界面（围栏管理接口 `FenceController` 已齐备）。
- 生产库需手工执行上面的 `message` 索引 DDL。

前端 / 文档：

- 首页天气文案为占位（后端暂无天气接口）。
- 前端设计 token 已收敛：`lib/**` 中（除 `core/theme/theme_palette.dart` 与 `app_theme.dart` 这两个定义层）
  **已无裸 `fontSize: <数字>` 与裸 `Color(0x...)`**；首页「运动目标 / 近期运动」已接入
  `home_goal_section.dart` / `home_activity_list.dart`，`home_page.dart` 收敛为 274 行的编排层。
  复核命令：`C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze lib test`（2026-10-03 通过，`No issues found!`）。
