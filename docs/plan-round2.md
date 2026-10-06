# 行迹 · 第二轮功能优化 plan

> 目标：聊天体验补全 + 数据修复 + 账号资料补全。
> 每项完成后独立验证并汇报，不做"一次性大改"。

---

## 背景调研结论（已确认）

| 项 | 现状 | 结论 |
|---|---|---|
| 聊天提醒 | 无 `flutter_local_notifications` / `vibration` 依赖 | **零提醒机制**，需从 0 建 |
| 消息分组 | `chat_page.dart` 仅 `ListView.builder` + `_Bubble` | 无时间分组 |
| 富媒体 | 仅 `image_picker`；后端 `message.type` 只支持 `1`=文本 | 需前后端 + DDL |
| 修改密码 | `UserController` 仅 `/me` GET/PUT/DELETE | 无改密接口 |
| 性别/年龄 | `user` 表无对应字段 | 需 DDL + DTO |
| 免打扰 | 无表无字段 | 需新表 |
| 运动计数 | `_isRun(a)=>a.type==1`；列表**不过滤 invalid** | 需先定位真实成因 |

---

## 阶段 P0 · 运动计数为 0 的根因定位（**先做，不猜**）

### 候选成因（按可能性排序）

1. **记录被标记 `invalid`**：反作弊或围栏校验命中 → 计入库但不计入成绩。
   现有 UI **完全不提示**，用户看到"跑了却没有记录"。
2. **距离算出 0**：`TrackSampler` 精度阈值 30m 过严，脏点被全部过滤。
3. **上传静默失败**：草稿保留但未上传，用户以为已保存。
4. **类型不匹配**：记成骑行（type=2）而首页只统计跑步。

### 诊断方式（服务器执行）

```sql
SELECT u.id, u.nickname,
       COUNT(a.id)                                   AS total,
       SUM(a.invalid = 1)                            AS invalid_cnt,
       SUM(a.distance_meters = 0)                    AS zero_dist,
       MIN(a.type) AS min_type, MAX(a.type) AS max_type
FROM user u LEFT JOIN activity a ON a.user_id = u.id
GROUP BY u.id, u.nickname;
```

**判定**：
- `invalid_cnt > 0` → 成因 1，修复 = **UI 明确提示 + 放宽误判阈值**
- `zero_dist > 0` → 成因 2，修复 = 调整精度/最小位移策略
- `total = 0` → 成因 3，修复 = 上传失败要显式报错且草稿可重试
- `min_type = max_type = 2` → 成因 4，修复 = 首页统计口径

### 交付
- [ ] 定位到具体成因并写出证据
- [ ] 针对性修复 + 回归测试

---

## 阶段 P1 · 后端（有依赖顺序，串行）

### P1.1 数据库迁移
`docs/migrations/002_profile_privacy_and_media.sql`

```sql
-- 用户资料扩展（性别 / 年龄 + 可见性）
ALTER TABLE `user`
  ADD COLUMN `gender`        TINYINT      NULL COMMENT '0=保密 1=男 2=女',
  ADD COLUMN `age`           INT          NULL COMMENT '年龄 1-120',
  ADD COLUMN `gender_public` TINYINT      NOT NULL DEFAULT 0 COMMENT '1=他人可见',
  ADD COLUMN `age_public`    TINYINT      NOT NULL DEFAULT 0 COMMENT '1=他人可见';

-- 消息富媒体（type: 1=文本 2=图片 3=表情）
ALTER TABLE `message`
  ADD COLUMN `media_url` VARCHAR(255) NULL,
  MODIFY COLUMN `content` VARCHAR(1000) NULL;

-- 聊天免打扰（按会话）
CREATE TABLE IF NOT EXISTS `chat_preference` (
  `id`         BIGINT   NOT NULL AUTO_INCREMENT,
  `user_id`    BIGINT   NOT NULL,
  `friend_id`  BIGINT   NOT NULL,
  `muted`      TINYINT  NOT NULL DEFAULT 0,
  `created_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at` DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  UNIQUE KEY `uk_user_friend` (`user_id`, `friend_id`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4;
```

**注意**：`schema.sql`（测试用 H2）需同步；生产用迁移脚本单独执行。

### P1.2 修改密码
- `PUT /api/v1/user/password`，body `{oldPassword, newPassword}`
- 校验：旧密码 BCrypt 比对；新密码长度 ≥8；新密码 ≠ 旧密码
- 成功后 **吊销所有 refresh token**（改密即踢下线，防被盗号后继续使用）
- 测试：旧密码错 → 400；新密码过短 → 400；成功 → 旧密码不可登录

### P1.3 资料可见性
- `PUT /api/v1/user/me` 扩展：`gender` / `age` / `genderPublic` / `agePublic`
- `GET /api/v1/user/{id}/profile`：**按可见性返回**
  - 本人：全返回
  - 他人：`gender_public=1` 才返回 gender，`age_public=1` 才返回 age
  - 手机号仍永不返回（既有约束）
- 测试：反射校验非本人不可见字段为 null

### P1.4 图片消息
- `POST /api/v1/upload/chat-image`（multipart）
  - 复用头像的安全实现：魔术字节识别、UUID 重命名、2MB 限制、**拒绝 SVG**
  - 落盘 `CHAT_IMAGE_DIR`
- `POST /api/v1/message/send` 支持 `type` + `mediaUrl`
  - 校验：`type=2` 必须有 `mediaUrl`；`type=1` 必须有非空 `content`
  - 离线推送正文：图片消息显示 `[图片]`
- 测试：伪造扩展名 / SVG / 超大 / 空 mediaUrl

### P1.5 免打扰
- `GET /api/v1/chat/preference` → 免打扰的好友 id 列表
- `PUT /api/v1/chat/preference`，body `{friendId, muted}`
- 推送时：若接收方对该会话免打扰 → **不推送**（仍落库）
- 测试：免打扰后 PushSender 不被调用

---

## 阶段 P2 · 前端（P1 完成后并行度更高）

### P2.1 消息按 5 分钟分组（用户明确要求）
- 在 `chat_page.dart` 渲染前做一次分组计算：
  ```
  相邻两条消息时间差 > 5 分钟 → 插入时间分隔条
  ```
- 分隔条格式：
  - 今天 → `14:32`
  - 昨天 → `昨天 14:32`
  - 本周内 → `周三 14:32`
  - 更早 → `10月1日 14:32`
- 抽成**纯函数** `groupMessagesByTime()` 便于单测（放 `lib/features/friends/utils/`）
- 测试：边界 4:59 / 5:01；跨天；空列表；单条

### P2.2 消息提醒（红点 + 震动 + 本地通知）
- 依赖：`flutter_local_notifications`、`vibration`（或 HapticFeedback）
- 触发点：`global_ws_provider` 收到 `message` 类型
- 行为矩阵：
  | 场景 | 行为 |
  |---|---|
  | 正在看该会话 | 不提醒（只更新列表） |
  | App 在前台、非当前会话 | 震动 + 本地通知 + 红点 |
  | App 在后台/关闭 | 依赖 FCM（**当前未接入**）→ 先做前台 |
  | 该会话免打扰 | **不震动不通知**，红点仍显示 |
- 注意：Android 13+ 需 `POST_NOTIFICATIONS` 运行时授权（manifest 已有）
- 测试：免打扰时 `shouldNotify() == false`

### P2.3 首页右上角三点菜单
- `home_top_bar.dart` 把「设置」按钮改为 `PopupMenuButton`
- 菜单项：`消息免打扰设置` / `编辑资料` / `修改密码` / `退出登录`
  （现有入口保留可达，不破坏已有路径）
- 免打扰设置页：好友列表 + 每行开关
- 注意：**修复已知的 Riverpod `setState during build`** —— 新菜单不要引入 build 期 watch

### P2.4 富媒体输入
- 输入栏加「+」→ 图片（`image_picker`）与「😀」→ 表情面板
- 表情：内置常用 emoji 网格（不引第三方库，避免包体膨胀）
- 表情包：一期做**内置贴图集**（`assets/stickers/`），type=3
- 图片消息渲染：圆角 + 点击全屏预览
- 测试：图片消息气泡渲染、表情插入光标位置

### P2.5 修改密码页
- 路由 `/change-password`
- 校验复用 `validators.dart`；成功后提示并回登录页

### P2.6 资料编辑 + 他人主页
- `profile_edit` 加性别（单选）、年龄（数字）、两个公开开关
- `user_profile_page`（他人主页）按后端可见性字段展示；未公开则不显示该行
- 测试：`genderPublic=false` 时他人主页不渲染性别

---

## 阶段 P3 · 验证

- [ ] 后端 `mvn -B -pl campus-run-server -am test` 全绿（当前 282 用例）
- [ ] 前端 `flutter test` 全绿
- [ ] `dart analyze lib test` → No issues found!
- [ ] **服务器迁移脚本执行 + 数据核对**
- [ ] 重新构建 APK 并真机安装
- [ ] 真机验收：聊天提醒/免打扰/分组/图片/表情/改密/资料可见性

---

## 风险与对策

| 风险 | 对策 |
|---|---|
| 生产库 ALTER 失败 | 迁移前 `mysqldump` 备份；字段可空 + 有默认值 |
| 本地通知在 MIUI 被杀 | 引导用户开自启动；前台通知作为兜底 |
| 图片消息增大存储 | 复用 2MB 限制 + 服务端不压缩（后续再优化） |
| 改密踢下线影响体验 | 仅吊销 refresh token，当前端自动跳登录页并提示 |
| 已知 Riverpod bug | 新增 provider 一律避免 build 期 watch 链 |

---

## 执行顺序

```
P0 定位（必须先做，决定 P1/P2 的修复方向）
 ↓
P1.1 DDL → P1.2 改密 → P1.3 资料可见性 → P1.4 图片 → P1.5 免打扰
 ↓
P2.1 分组 → P2.2 提醒 → P2.3 三点菜单 → P2.4 富媒体 → P2.5 改密页 → P2.6 资料
 ↓
P3 验证
```
