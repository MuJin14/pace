# 架构、目录与规范

技术栈、目录结构、常用命令、测试现状、代码规范。

## 技术栈
| 层 | 实际使用 |
|----|----------|
| 后端语言/框架 | Java 17、Spring Boot 3.2.5 |
| 数据库 | MySQL 8（生产/本地）、H2 内存库（测试） |
| ORM | MyBatis-Plus 3.5.7 |
| 鉴权 | Spring Security + JWT（jjwt 0.12.6）；**双令牌** access(2h) + refresh(30d)，入口限流 |
| 实时通信 | Spring WebSocket（原生 handler，非 STOMP） |
| 前端 | Flutter（Dart SDK `^3.7.2`）+ Riverpod 3 + go_router 17 + Dio 5 |
| 前端其他依赖 | `flutter_secure_storage`、`shared_preferences`、`web_socket_channel`、`geolocator`、`flutter_map`、`latlong2`、`image_picker`（选头像） |
| 覆盖率 | JaCoCo 0.8.12 |

> **Redis 已不在技术栈内**：`campus-run-server/pom.xml` 没有 Redis 依赖，代码中 0 处 Redis 引用，
> `docker-compose.yml` 也只起 MySQL。排行榜完全基于 MySQL 的 `leaderboard_stats` 表实现，
> 设计文档里「Redis ZSET 排行榜」是**已废弃的历史方案**，不要再按它写代码。

## 目录结构
```
project/
├── campus-run-backend/          后端 Maven 多模块工程
│   ├── pom.xml                  聚合 POM（Spring Boot 3.2.5 parent，JaCoCo 配置）
│   ├── docker-compose.yml       本地依赖：仅 MySQL 8
│   ├── campus-run-common/       公共模块：Result<T> 统一返回体、错误码、业务异常
│   ├── campus-run-server/       可运行应用：全部业务代码 + 测试
│   │   ├── src/main/java/com/campusrun/server/
│   │   │   ├── controller/      9 个 REST 控制器（不写业务逻辑）
│   │   │   ├── service/impl/    9 个业务实现（事务边界）
│   │   │   ├── mapper/          MyBatis-Plus Mapper
│   │   │   ├── entity/ dto/     Entity 与 DTO 分离
│   │   │   ├── security/        JWT 生成/校验、认证过滤器
│   │   │   ├── websocket/       握手鉴权 + 聊天 handler + 会话管理
│   │   │   ├── cache/           FenceCache（应用内缓存，非 Redis）
│   │   │   ├── event/           领域事件（好友、勋章）
│   │   │   ├── task/            定时任务（排行榜/目标/勋章/会话清理）
│   │   │   └── util/            GpsUtil（平滑+抽稀）、UniqueIdGenerator
│   │   ├── src/main/resources/  application.yml、schema.sql
│   │   └── src/test/            27 个测试类 + H2 测试配置
│   └── docs/                    api.md（831 行完整接口文档）、schema.sql、admin-init.md
├── campus-run-app/              Flutter 客户端
│   ├── lib/core/                config/network/router/storage/theme/utils/widgets/ws
│   ├── lib/data/                models（15 个 DTO）+ repositories（7 个）
│   ├── lib/features/            activity/auth/badges/friends/goals/home/leaderboard/notifications/profile
│   ├── design/                  首页设计规格 PNG（home_spec / home_loaded / home_empty）★设计资产
│   └── test/                    单元测试（目前只有 widget_test.dart）
├── flutter-design/flutter_ui/   设计稿导出的 Flutter 参考工程（仅参考，非生产代码）
├── 前端页面示例/                4 张 UI 示例 PNG ★设计资产
├── AGENTS.md                    本文件（权威文档）
└── claude.md / CLAUDE.md        同一文件，指向本文件
```

`runApp_frame.txt`、`extra_suggest.md` 是早期设计原文，**当前不在仓库里**；其中的有效结论已内联到本文档。

### 后端模块职责

- `campus-run-common`：`com.campusrun.common.result.Result<T>`、`com.campusrun.common.exception`（错误码 + 业务异常）。无测试代码。
- `campus-run-server`：Spring Boot 可运行应用，包含全部业务、WebSocket、定时任务；所有测试都在这里。

### 前端分层

- `core/`：跨域基础设施。`config/app_config.dart`（API 地址）、`network/`（Dio 封装）、`router/app_router.dart`（go_router 路由表）、`storage/`（token 持久化）、`theme/`（设计系统：`app_theme.dart` 调色板、`app_font_size.dart` 字号 token、`app_spacing.dart` 间距 token、`theme_palette.dart` 颜色 token）、`widgets/`（共享组件，`app_widgets.dart` 为 barrel 出口）、`ws/`（WebSocket 客户端）。
- `data/`：`models/` 纯数据模型，`repositories/` 调后端接口，不写 UI。
- `features/`：按业务域拆分，每个域内 `pages/` + `providers/` + 可选 `widgets/`。
- 已注册路由：`/splash` `/login` `/register` `/home` `/leaderboard` `/friends` `/profile` `/activity` `/start-run` `/run-result` `/activity/:id` `/chat/:friendId` `/friends/search` `/goals` `/badges` `/notifications`。

## 测试与覆盖率现状
- 后端：**282 个用例，全绿**；JaCoCo 覆盖率数字会随代码变动，引用前请重跑 `mvn -B -pl campus-run-server -am test` 后打开 `campus-run-server/target/site/jacoco/index.html`。
- 测试环境：`src/test/resources/application-test.yml` 用 H2 内存库（`MODE=MySQL`），**不依赖本地 MySQL**；`src/test/resources/schema.sql` 建表。
- 前端：`test/` 下 11 个文件 / **207 个用例全绿**（validators / formatters / coord_transform / models / ws_message / widgets / home_sections / widget_test / chat_ownership / account_isolation / run_tracking）。
  另有 2 个**评估用**脚本不属于断言测试：`visual_qa_test.dart`（渲染 30 张截图，其中 flutter_map 那条因测试环境缺 path_provider 插件会失败）与 `qa_contrast_check.dart`（打印 WCAG 对比度实测值）。这两者请勿计入 CI 断言。

## 代码规范
- Controller 不写业务逻辑
- Service 负责事务
- DTO 与 Entity 分离
- 统一返回 Result<T>
- 全局异常处理
- 密码必须 BCrypt
- 禁止提交密钥和真实配置
- 前端：颜色/字号/间距一律走 `core/theme` 的 token，不写裸 `Color(0x...)` 与裸 `fontSize: <数字>`
