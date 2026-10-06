# 校园跑（Campus Run）后端

面向高校学生的运动记录与社交 App 后端，支持跑步/骑行轨迹记录、排行榜、好友聊天、
校园围栏、运动目标与勋章体系。

> 仓库级开发约定与领域规则见根目录 [`AGENTS.md`](../AGENTS.md)（唯一权威文档）。

## 技术栈

Java 17 · Spring Boot 3.2.5 · MySQL 8（测试用 H2 内存库）· MyBatis-Plus 3.5.7 ·
Spring Security + JWT（jjwt 0.12.6）· WebSocket · JaCoCo 0.8.12

> **不使用 Redis**：`campus-run-server/pom.xml` 无 Redis 依赖，代码中无 Redis 引用，
> `docker-compose.yml` 只启动 MySQL。排行榜完全基于 MySQL 的 `leaderboard_stats` 表实现。

## 环境要求

- JDK 17
- Maven 3.9+
- MySQL 8.0+（用下面的 `docker compose up -d` 起一个即可；测试不需要它）

## 本地启动

1. 启动 MySQL（`docker-compose.yml` 只包含 MySQL 8，端口 3306，root/root，库名 `campus_run`）：

   ```bash
   docker compose up -d
   ```

   若不用 Docker，也可以自建数据库：

   ```sql
   CREATE DATABASE campus_run DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

2. 导入表结构：

   ```bash
   mysql -u root -p campus_run < docs/schema.sql
   ```

3. 如需改账号密码，编辑 `campus-run-server/src/main/resources/application.yml`
   （默认 `root` / `root`，仅供本地开发；生产环境请勿提交真实配置）。

4. 启动后端（多模块工程请带上 `-pl campus-run-server -am`，指定运行 server 模块）：

   ```bash
   mvn -B -pl campus-run-server -am spring-boot:run
   ```

   服务默认监听 `http://localhost:8080`。

## 运行测试

```bash
# 推荐：只跑 server 模块并连带构建 common
mvn -B -pl campus-run-server -am test

# 等价写法（在 campus-run-backend 根目录跑两个模块）
mvn test

# 单个测试类 / 单个方法
mvn -B -pl campus-run-server -am test -Dtest=MessageServiceImplTest
mvn -B -pl campus-run-server -am test -Dtest=MessageServiceImplTest#方法名
```

- 测试环境使用 H2 内存库（`src/test/resources/application-test.yml`，`MODE=MySQL`），**不依赖本地 MySQL**。
- 当前 **195 个测试用例全部通过**（`Tests run: 195, Failures: 0, Errors: 0, Skipped: 0`，
  2026-10-03 实测），分布在 27 个测试类中。

## 测试覆盖率

跑完 `mvn -B -pl campus-run-server -am test` 后打开 `campus-run-server/target/site/jacoco/index.html`：

- 指令覆盖率 **约 88%**（报告页显示 87%，即 4704/5353），已排除 `dto` / `entity` / `enums` / `config` 与启动类；
- 分支覆盖率 **约 72%**（263/363）。

数字会随代码变动，引用前请重跑或标注为「约」。

## 项目结构

- `campus-run-common/`：公共模块 —— 统一返回体 `Result<T>`、错误码、业务异常（无测试代码）
- `campus-run-server/`：可运行应用
  - `controller/` 9 个 REST 控制器（不写业务逻辑）
  - `service/impl/` 业务实现（事务边界）
  - `mapper/`、`entity/`、`dto/`（请求/响应/WebSocket 三类 DTO）
  - `security/` JWT 生成校验与认证过滤器；`websocket/` 握手鉴权、聊天 handler、会话管理
  - `cache/` `FenceCache`（应用内缓存，非 Redis）；`event/` 领域事件；`task/` 定时任务
  - `util/` `GpsUtil`（轨迹平滑 + 抽稀）、`UniqueIdGenerator`
- `docs/`：`api.md`（完整接口文档）、`schema.sql`（建表 DDL）、`admin-init.md`

## 管理员初始化

详见 `docs/admin-init.md`。将普通用户设为管理员：

```sql
UPDATE `user` SET `role` = 1 WHERE `phone` = '13800138000';
```

修改后该用户需重新登录，新角色才会随 JWT 生效。

## 主要接口

详见 `docs/api.md`。一级路径：

- `/api/v1/auth`：注册、登录
- `/api/v1/activity`：运动记录
- `/api/v1/leaderboard`：排行榜
- `/api/v1/friend`：好友关系
- `/api/v1/message`：聊天消息历史、标记已读
- `/api/v1/goals`：运动目标
- `/api/v1/badges`：勋章
- `/api/v1/admin/fences`：校园围栏（管理员）
- `/ws?token=<jwt>`：WebSocket 聊天（握手用 JWT 鉴权）

## 数据库升级说明

若你的库是较早版本创建的，需要手工执行一次下面的 DDL（`docs/schema.sql` 已包含该索引，
新建库无需额外操作；执行前请先确认索引不存在，避免重复添加报错）：

```sql
ALTER TABLE message ADD KEY idx_receiver_sender_read (receiver_id, sender_id, read_at);
```

该索引支撑「查询某个接收方的未读消息」与显式标记已读接口。

## 已实现能力（近期补齐，勿再列为 TODO）

- **消息已读回执**：`ChatMessageResponse.readAt`（毫秒时间戳，`null` = 未读）；
  拉取 `GET /api/v1/message/history` 时隐式标记好友发给我的未读消息；
  显式 `POST /api/v1/message/read?messageIds=1&messageIds=2`（整批校验权限，非本人接收返回 403，幂等）；
  标记后向发送方推送 WebSocket `read_receipt`：`data = { readerId, friendId, messageIds, readAt }`。
  详见 `docs/api.md` 第 16 / 16.1 节与 WebSocket 消息类型表。
- **运动目标周期服务端推导**：`POST /api/v1/goals` 只需 `periodType` + `targetDistanceMeters`；
  `weekly`（本周一~周日）/ `monthly`（当月 1 日~月末）由服务端按 `Asia/Shanghai` 推导，客户端传值被忽略；
  `custom` 必填 `startDate`/`endDate`，缺失或 `endDate < startDate` 返回 400。详见 `docs/api.md` 第 22 节。

## 已知限制 / TODO

- 单端在线，多端同时登录的会话同步尚未实现
- 消息不支持图片等富媒体，`type` 目前只有 `1`=文本
- 管理员暂无前端管理界面（围栏管理接口已齐备，需用 HTTP 工具调用）
- 生产库需手工执行上面的 `message` 索引 DDL（旧库升级时）
