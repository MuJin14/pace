# AGENTS.md

本文件是仓库的**入口与索引**。详细内容拆到 [`docs/`](./docs/) 下按主题维护，
避免单文件过大被工具截断（本文件曾超过 64KB 上限而被静默截断，
后半部分实际上「写了等于没写」）。

## 文档维护约定（先读这一节）

- **本文件只放**：项目速览、命令速查、文档索引、设计资产清单。
- **详细内容一律写进 `docs/` 对应主题的文件**，不要在本文件里展开。
- `CLAUDE.md` 只保留「指向本文件的简短说明」，不复制长文档，避免两份漂移。
- 子项目上手文档：`campus-run-backend/README.md`、`campus-run-app/README.md`。
  与本文档冲突时以本文档为准。
- ⚠️ Windows 大小写不敏感：`CLAUDE.md` 与 `claude.md` 是**同一个文件**
  （git 跟踪小写名），不要创建第二个。

## 文档索引

| 主题 | 文件 | 什么时候读 |
|---|---|---|
| 领域约定 | [docs/domain-conventions.md](docs/domain-conventions.md) | 改业务逻辑前**必读**。都是「曾出过 bug、务必保持」的约定 |
| 跑步核心链路 | [docs/run-tracking.md](docs/run-tracking.md) | 碰定位/距离/反作弊/轨迹上传时 |
| 架构与规范 | [docs/architecture.md](docs/architecture.md) | 技术栈、目录结构、代码规范、测试现状 |
| 鉴权与后端专题 | [docs/backend-security.md](docs/backend-security.md) | 双令牌/限流、离线推送、WebSocket、已读回执、目标周期 |
| 排行榜与其余决策 | [docs/leaderboard.md](docs/leaderboard.md) | 排行榜、好友拒绝逻辑、设计资产 |
| 真机调试 | [docs/android-debug.md](docs/android-debug.md) | 上真机 / 定位不工作 / 连不上后端时 |
| 部署 | [docs/deployment.md](docs/deployment.md) | 部署服务器 |
| 各轮优化记录 | [docs/history-rounds.md](docs/history-rounds.md) | 想知道「某个设计为什么长这样」时 |
| 官网与 HTTPS | [campus-run-backend/docs/site.md](campus-run-backend/docs/site.md) | 改官网 / Cloudflare / 证书时 |
| App 发版 | [campus-run-backend/docs/release.md](campus-run-backend/docs/release.md) | 发新版本 APK |
| 管理后台 | [campus-run-backend/docs/admin.md](campus-run-backend/docs/admin.md) | 开管理员 / 帮用户重置密码 |
| 后端接口文档 | [campus-run-backend/docs/api.md](campus-run-backend/docs/api.md) | 查具体接口参数 |
| 推送接入 | [campus-run-backend/docs/push-setup.md](campus-run-backend/docs/push-setup.md) | 接 Firebase |

## 项目速览

**校园跑 Campus Run**：面向高校学生的运动记录与社交 App
（跑步/骑行轨迹 + 排行榜 + 好友聊天 + 专属模式）。

| 项 | 现状 |
|---|---|
| 后端 | Java 17 · Spring Boot 3.2.5 · MySQL 8（测试用 H2）· MyBatis-Plus · Spring Security + JWT · WebSocket |
| 前端 | Flutter（Dart `^3.7.2`）+ Riverpod 3 + go_router 17 + Dio 5 |
| 阶段 | 四阶段（注册登录/运动记录 → 排行榜/轨迹 → 好友/聊天 → 围栏/目标/勋章）**均已实现** |
| 后端测试 | **400 个用例全绿** |
| 前端测试 | **415 个断言用例全绿**（`visual_qa_test.dart` / `qa_contrast_check.dart` 是评估脚本，不计入） |
| 线上地址 | App 用 `http://122.51.191.145:8080`（直连；域名方案因证书问题已废弃） |
| App 版本 | `campus-run-app/pubspec.yaml` 的 `version:`，发版见 release.md |

> **Redis 不在技术栈内**。排行榜完全基于 MySQL 的 `leaderboard_stats`。
> 设计文档里「Redis ZSET 排行榜」是**已废弃的历史方案**，不要按它写代码。

## 常用命令

后端（在 `campus-run-backend/` 下）：

```bash
# 本地 MySQL（docker-compose.yml 里只有 MySQL，没有 Redis）
docker compose up -d

# 全量测试（H2 内存库，不需要本地 MySQL）—— 推荐
mvn -B -pl campus-run-server -am test
# ⚠️ 必须带 clean：不 clean 时 JaCoCo 会对已插桩的 class 再插桩而报错

# 单个测试类 / 方法
mvn -B -pl campus-run-server -am test -Dtest=MessageServiceImplTest
mvn -B -pl campus-run-server -am test -Dtest=MessageServiceImplTest#方法名 \
    -Dsurefire.failIfNoSpecifiedTests=false

# 覆盖率：跑完 test 后开 campus-run-server/target/site/jacoco/index.html

# 启动应用（多模块工程必须带 -pl campus-run-server -am）
mvn -B -pl campus-run-server -am spring-boot:run
```

前端（在 `campus-run-app/` 下）：

```bash
flutter pub get
flutter run
flutter test
flutter analyze
```

> **环境坑（本机）**：`flutter` 包装脚本在无网络时会卡在 `git fetch --tags` 不返回。
> 此时静态检查直接用原始 Dart SDK：
> `C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .`
> `flutter test` 也要加 `--no-version-check --no-pub`。

> **构建 APK 必须用 ASCII 路径**：项目路径含中文，从真实路径构建 Gradle 会失败
> （`Cannot invoke "java.io.File.exists()" because "parent" is null`）。
> 用 `subst` 映射盘，且**必须与构建在同一条命令里**（`subst` 只在创建它的会话有效）。
> 详见 [docs/android-debug.md](docs/android-debug.md)。

## 设计资产（必须保持可提交）

| 路径 | 内容 |
|------|------|
| `campus-run-app/design/home_spec.png` | 首页信息架构优化规格板（组件拆分的依据） |
| `campus-run-app/design/home_loaded.png` / `home_empty.png` | 首页数据态 / 空态 |
| `前端页面示例/*.png` | 4 张 UI 示例（规格说明板、页面 1） |
| `flutter-design/flutter_ui/` | 设计稿导出的参考工程（含字体、SVG、原始 Dart 稿） |

这些 PNG 是设计资产，`.gitignore` **不得忽略**（见仓库根 `.gitignore` 末尾的显式说明）。
