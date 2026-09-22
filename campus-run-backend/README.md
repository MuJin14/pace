# 校园跑（Campus Run）后端

面向高校学生的运动记录与社交 App 后端，支持跑步/骑行轨迹记录、排行榜、好友聊天、
校园围栏、运动目标与勋章体系。

## 技术栈

Java 17 · Spring Boot 3.2 · MySQL 8 · MyBatis-Plus · Spring Security + JWT · WebSocket

## 环境要求

- JDK 17
- Maven 3.9+
- MySQL 8.0+

## 本地启动

1. 创建数据库：

   ```sql
   CREATE DATABASE campus_run DEFAULT CHARACTER SET utf8mb4 COLLATE utf8mb4_unicode_ci;
   ```

2. 导入表结构：

   ```bash
   mysql -u root -p campus_run < docs/schema.sql
   ```

3. 修改 `campus-run-server/src/main/resources/application.yml` 中的数据库账号与密码。

4. 启动后端：

   ```bash
   mvn spring-boot:run
   ```

## 运行测试

```bash
mvn test
```

测试环境使用 H2 内存库（`application-test.yml`），不依赖本地 MySQL。

## 项目结构

- `campus-run-common/`：通用返回体（Result）、业务异常、错误码
- `campus-run-server/`：业务代码（controller / service / mapper / entity / websocket / task）
- `docs/`：schema.sql、api.md、admin-init.md

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
- `/api/v1/message`：聊天消息历史
- `/api/v1/goals`：运动目标
- `/api/v1/badges`：勋章
- `/api/v1/admin/fences`：校园围栏（管理员）

## 测试覆盖率

运行 `mvn test` 后查看 `campus-run-server/target/site/jacoco/index.html`，当前指令覆盖率约 86.6%。

## 已知限制 / TODO

- 单端在线，多端同时登录的会话同步尚未实现
- 消息不支持图片等富媒体
- 消息已读回执未实现（`read_at` 字段已预留）
- 管理员暂无前端管理界面
- `GoalService.create` 目前要求客户端传 `startDate`/`endDate`；应改为服务端根据 `periodType` 自动推导（`weekly` = 本周一至周日，`monthly` = 本月 1 日至月末），`custom` 类型才由客户端指定日期
