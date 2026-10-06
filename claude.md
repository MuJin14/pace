# CLAUDE.md

本文件面向 Claude Code。

**入口是 [`AGENTS.md`](./AGENTS.md)，详细内容按主题拆在 [`docs/`](./docs/) 下。**

> 为什么拆：`AGENTS.md` 曾经是单一大文件，超过工具 64KB 上限后被**静默截断** ——
> 后半部分实际「写了等于没写」。现在它只做索引，各主题独立成文。

## 文档维护约定

- **`AGENTS.md` 只放**：项目速览、命令速查、文档索引、设计资产清单。
- **详细内容写进 `docs/` 对应主题的文件**（领域约定 / 跑步链路 / 架构规范 /
  鉴权与后端专题 / 排行榜 / 真机调试 / 部署 / 各轮记录）。
- `CLAUDE.md` 只保留这份简短入口，不复制长文档。
- 子项目上手文档：`campus-run-backend/README.md`、`campus-run-app/README.md`。
- ⚠️ Windows 大小写不敏感：`CLAUDE.md` 与 `claude.md` 是**同一个文件**
  （git 跟踪小写名），不要创建第二个。

## 项目速览

**校园跑 Campus Run**：面向高校学生的运动记录与社交 App
（跑步/骑行轨迹 + 排行榜 + 好友聊天 + 专属模式）。

| 项 | 现状 |
|----|------|
| 技术栈 | Java 17 · Spring Boot 3.2.5 · MySQL 8（测试用 H2） · MyBatis-Plus · Spring Security + JWT · WebSocket；Flutter（Dart `^3.7.2`）+ Riverpod 3 + go_router 17 + Dio 5 |
| 阶段 | 四阶段（注册登录/运动记录 → 排行榜/轨迹 → 好友/聊天 → 围栏/目标/勋章）**均已实现**，非设计阶段 |
| 后端 | Maven 多模块（`campus-run-common` + `campus-run-server`），**400 个测试全绿** |
| 前端 | `campus-run-app`，`core`/`data`/`features` 分层，**415 个断言测试全绿** |
| 线上 | App 用 `http://122.51.191.145:8080`（直连；域名方案因证书问题已废弃） |
| 排行榜 | 完全基于 MySQL `leaderboard_stats`；**Redis 方案已废弃**（无依赖、无代码） |

常用命令（完整版见 [`AGENTS.md`](./AGENTS.md)）：

```bash
# 后端（campus-run-backend/）：H2 内存库，不需要本地 MySQL
mvn -B -pl campus-run-server -am clean test    # ⚠️ 必须带 clean（JaCoCo 插桩）
mvn -B -pl campus-run-server -am spring-boot:run

# 前端（campus-run-app/）
flutter test --no-version-check --no-pub
# 无网络时 flutter 包装脚本会卡在 git version check，改用：
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .
```

## 该读哪个文件

| 你要做的事 | 读这个 |
|---|---|
| 改业务逻辑 | [docs/domain-conventions.md](docs/domain-conventions.md) **（必读）** |
| 碰定位/距离/反作弊 | [docs/run-tracking.md](docs/run-tracking.md) |
| 上真机 / 定位不工作 | [docs/android-debug.md](docs/android-debug.md) |
| 部署服务器 | [docs/deployment.md](docs/deployment.md) |
| 发新版 APK | [campus-run-backend/docs/release.md](campus-run-backend/docs/release.md) |
| 改官网 / Cloudflare | [campus-run-backend/docs/site.md](campus-run-backend/docs/site.md) |
| 帮用户重置密码 | [campus-run-backend/docs/admin.md](campus-run-backend/docs/admin.md) |
| 想知道某个设计为什么这样 | [docs/history-rounds.md](docs/history-rounds.md) |
