# 领域约定

业务规则与「曾经踩过、务必保持」的约定。改相关代码前先读。

## 关键领域约定
- 专属 ID：**8 位纯数字**（左侧补零，如 `04231786`），全局唯一，由 `UniqueIdGenerator` 生成。
  历史上是 `CR-XXXXXXXX`，已废弃——带字母前缀会让用户在好友搜索框里犹豫「要不要连 CR- 一起输」。
  界面上一律以 `ID 04231786` 的形式展示（`Formatters.uniqueId`），该函数会自动剥掉历史 `CR-` 前缀。
  已有 `CR-` 数据可执行一次性迁移：`UPDATE user SET unique_id = SUBSTRING(unique_id, 4) WHERE unique_id LIKE 'CR-%';`
- **好友搜索**（微信式社交模型）：按「专属 ID / 昵称 / 手机号」模糊匹配，**自己与已有好友同样会被搜到并展示**，
  由服务端返回的 `relation` 字段（`self` / `friend` / `pending_outgoing` / `pending_incoming` / `none`）决定操作按钮：
  自己→看主页、好友→发消息、我申请过→等待中、对方申请我→通过验证、无关系→添加好友。
  **按钮状态一律以服务端 relation 为准**，前端不自行推断，避免「看起来能聊但发送被拒」这类不一致。
- **用户主页**：`GET /api/v1/user/{userId}/profile`，任意用户可看（含自己），返回昵称、专属 ID、头像、
  加入时间、运动汇总（累计距离/次数/连续天数）与 relation。
  **刻意不返回手机号** —— 主页对任何搜到的人可见，手机号只在 `/me` 对自己可见；已有单测用反射兜底防回归。
  前端路由 `/user/:id`，入口有四处：「我的」页的「我的主页」、搜索结果的整卡点击、
  聊天页标题栏（头像+昵称可点）、以及聊天页右上角「三个点 → 查看 TA 的主页」。
- **编辑资料**：`PUT /api/v1/user/me`（昵称 1-20 字、头像 URL，两者均可空）。
  **null = 不修改**（PATCH 语义）：客户端只传头像时不会把昵称清空；头像传空串 = 清空，回到昵称首字兜底。
  手机号与专属 ID 不可改（前者是账号标识，后者是别人加你的凭据）。
- **头像上传**：POST /api/v1/upload/avatar（multipart，字段名 `file`），返回 `{url}`，
  再通过 `PUT /api/v1/user/me` 写入 `avatarUrl` —— 上传与「设为头像」是两个动作，
  上传失败不会把已有资料改坏。
  **安全实现要点**（都不是可选项）：按**魔术字节**识别 JPG/PNG/WebP（不信扩展名与
  Content-Type，否则 `shell.jpg` 里放 PHP 就能绕过）；**服务端用 UUID 重命名**（防路径穿越与同名覆盖）；
  落盘前校验目标路径仍在 `app.upload-dir` 之内；限制 2MB（Spring multipart 配置 + 服务层二次校验）。
  **拒绝 SVG**：SVG 可内嵌 `<script>`，当图片渲染等于 XSS。
  静态访问 `/uploads/**` 需在 Spring Security 中 `permitAll`（`<img>` 不会带 Authorization 头），
  且资源 location 必须是 `file:` 前缀 + **正斜杠** + 结尾 `/` —— 直接用
  `Path.toUri()` 在 Windows 上得到 `file:///C:/...`，Spring 解析不到，表现为「上传成功但图片 404」。
  相关配置：`app.upload-dir` / `app.public-base-url`（放在 Nginx 后要改成对外域名，否则返回的 URL 客户端打不开）。
  已有 7 个安全用例：`FileStorageServiceTest`（伪装图片 / SVG / 超大 / 空文件 / 路径穿越 / 同名覆盖）。
- **他人运动数据 / 勋章墙**：`GET /api/v1/user/{userId}/activities`、`GET /api/v1/user/{userId}/badges`。
  **仅好友（或自己）可见，非好友返回 HTTP 403 + body `code=403`**。
  为此引入了 `ForbiddenException`（`campus-run-common`）并在全局处理器上标注 `@ResponseStatus(FORBIDDEN)`：
  业务异常默认按 HTTP 200 返回，但权限拒绝**必须让状态码本身是 403**，否则调用方无法仅凭状态码区分
  「没权限」与「对方没数据」，前端会把越权渲染成空态。不能用 Spring Security 的 `AccessDeniedException`
  ——`campus-run-common` 不依赖 spring-security。
  已有两层测试固化：Service 层断言抛 `ForbiddenException` 且**权限不通过时不去查数据**；
  HTTP 层（`UserSocialDataAccessTest`）断言陌生人 403 / 好友 200 / 未登录 401。
- **聊天页**采用微信式结构：标题栏 = 对方头像 + 昵称（整块可点进主页），右上角「三个点」菜单提供
  「查看 TA 的主页」与「查看聊天记录」（`/chat/:friendId/history`，只读、最新在上）。
  跳转聊天时通过 `extra` 传 `{'name':…, 'avatarUrl':…}`，标题栏先渲染传入头像再由 profile 覆盖，避免闪烁。
- **账号数据隔离（曾出一类 bug，务必按此约定写）**：任何返回「当前登录用户私有数据」的 provider
  **必须先调用 `ref.watchUserId()`**（`lib/core/providers/account_scope.dart`）。
  这些 provider 是全局缓存、默认与账号无关：同一设备 A 退出、B 登录后缓存不失效，
  B 会读到 **A 的数据**。已出过的表现：
  「自己的账号出现在自己的好友列表里」（B 看到 A 的好友列表，而 A 的好友恰好是 B）。
  已按此约定加固：`friendListProvider` / `friendRequestsProvider` / `friendSearchProvider`
  （relation 是相对当前用户算的）/ `activityListProvider` / `goalListProvider` /
  `badgeMineProvider` / `messageHistoryProvider` / `myRankProvider` / 首页 `_lastWeekRankProvider`。
  `watchUserId()` 同时解决了「登出瞬间带旧令牌打一次必然 401 的请求」：未登录时直接返回空数据、不发请求。
  **参数已带 userId 的 family provider**（如 `userProfileProvider(id)`）天然分账号，无需调用。
  回归由 `test/account_isolation_test.dart` 固化（已验：去掉 `watchUserId` 该测试即失败）。
- **未读红点 / 当前会话也必须随账号重置**：`friendBadgeProvider`（未读红点）与
  `currentChatFriendIdProvider`（当前打开的会话）都是**全局内存状态，登出不会清**。
  不重置会有两个 bug：新账号继承上一个账号的红点；以及若上一个会话的好友恰好也是新账号的好友，
  新消息会被 `app.dart` 误判成「正在看这个会话」而**被吞掉 —— 表现为收到消息没有提醒**。
  两者均已改为在 `build()` 里 `ref.watchUserId()`，账号一变即重建归零。
- **Web 上传必须用 `MultipartFile.fromBytes`，绝不能用 `MultipartFile.fromFile`**：
  `fromFile` 依赖 `dart:io`，Web 上其构造函数直接抛
  `UnsupportedError("MultipartFile is only supported where dart:io is available.")`。
  更隐蔽的是 **dart2js 会因此把 `fromFile` 之后的代码判定为不可达，
  把整个方法与接口路径字符串一起 tree-shake 掉** —— 症状是「前端选了图毫无反应」，
  而且产物里**搜不到 `/api/v1/upload/avatar`**。排查此类「代码写了但产物里没有」的问题时，
  用 `python` 对 `build/web/main.dart.js` 做字节级字符串搜索比 `Select-String` 可靠
  （后者受 GBK 控制台影响，且 Dart 会把非 ASCII 转义成 `\uXXXX`）。
  Web 端 `XFile.path` 是 blob URL，必须先 `readAsBytes()` 再上传。
- **消息归属判定（曾出一处 bug，务必按此约定写）**：气泡左右只由 `message.senderId == 当前登录 userId`
  决定，**与会话对象 `friendId` 无关**。
  ⚠️ 渲染路径**必须使用 `ref.watch(authProvider)` 的结果**，不能用 `ref.read(authProvider)`：
  `read` 只读一次、不订阅，首帧登录态尚未解析完成时会拿到 null（userId=0），
  于是 `senderId == 0` 恒为 false，**所有消息都被判成「收到的」**。
  表现就是「A 发给 B 的消息，在 B 侧显示成 B 自己发的」。回归由 `test/chat_ownership_test.dart` 固化。
  事件回调（如乐观消息的 `senderId`）用 `ref.read` 取即时值是正确的。
- 运动类型：`1` = 跑步，`2` = 骑行。
- 核心表：`user`、`activity`（运动记录，轨迹以 JSON 存储）、`friendship`、`message`、`leaderboard_stats`、`goal`、`badge`、`user_badge`、`campus_fence`（完整 DDL 见 `campus-run-backend/docs/schema.sql`）。
- GPS 轨迹：距离用 Haversine 累加（`GpsUtil`）。**反作弊已实现部分**：`TrackAnomalyDetector` 做轨迹物理合理性校验（相邻点瞬时速度上限、加速度上限、全程平均速度上限、重复时间戳位移、原地漂移、未来时间戳），命中则置 `activity.invalid=1` 并把原因写入 `invalid_reason`，**不计入排行榜/目标/勋章**；专属模式下再叠加地理围栏（轨迹点在围栏内的比例 ≥ `1 - allowedOutsideRatio`）。
- **尚未实现（原文档曾误标为已实现）**：滑动平均平滑、道格拉斯-普克抽稀、随机打卡点、步频校验。
- 统一返回 `Result<T>`，全局异常处理；密码 BCrypt；禁止提交密钥与真实配置（`application.yml` 里的 JWT secret / 数据库口令仅本地开发用）。
