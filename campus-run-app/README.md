# 校园跑 Campus Run · Flutter 客户端（`campus_run_app`）

面向高校学生的运动记录与社交 App 客户端：跑步/骑行轨迹记录、排行榜、好友聊天、运动目标与勋章、
校园围栏防作弊。后端为仓库同级目录下的 `campus-run-backend`（Spring Boot）。

> 仓库级开发约定、目录总览与领域规则见根目录 [`AGENTS.md`](../AGENTS.md)（唯一权威文档）。

## 技术栈（对照 `pubspec.yaml`）

| 用途 | 依赖 |
|------|------|
| 框架 | Flutter，Dart SDK `^3.7.2` |
| 状态管理 | `flutter_riverpod` ^3.3.2（`Provider` / `FutureProvider` / `NotifierProvider` / `AsyncNotifierProvider` / `StreamProvider`，无 codegen） |
| 路由 | `go_router` ^17.0.0 |
| 网络 | `dio` ^5.11.1 |
| 实时通信 | `web_socket_channel` ^2.4.5（`lib/core/ws/`） |
| 本地存储 | `flutter_secure_storage` ^10.3.4（token）、`shared_preferences` ^2.5.3 |
| 定位与地图 | `geolocator` ^12.0.0、`flutter_map` ^8.3.2、`latlong2` ^0.10.1 |
| 图标 | `cupertino_icons` |
| 开发依赖 | `flutter_test`、`flutter_lints` ^5.0.0 |

**图表没有第三方依赖**：首页的环形进度、7 柱跑量图分别是自绘组件
`lib/core/widgets/app_progress_ring.dart` 与 `app_mini_bar_chart.dart`（`CustomPaint`），
所以 `pubspec.yaml` 里没有 `fl_chart`。

## 目录结构

```
lib/
├── main.dart / app.dart          入口与 MaterialApp 装配
├── core/                         跨域基础设施
│   ├── config/app_config.dart    API 地址（平台默认 + --dart-define 覆盖）
│   ├── network/                  Dio 实例、拦截器、统一错误映射
│   ├── router/app_router.dart    go_router 路由表（16 条）
│   ├── storage/                  token 安全存储
│   ├── theme/                    设计系统：app_theme.dart（调色板/圆角/阴影/字重）、
│   │                             app_font_size.dart（字号 token）、app_spacing.dart（间距 token）、
│   │                             theme_palette.dart（颜色 token 定义层）
│   ├── utils/                    formatters（距离/配速/时间）、coord_transform（坐标转换）
│   ├── validators.dart           表单校验（手机号、密码）
│   ├── widgets/                  共享组件（app_widgets.dart 为 barrel 出口）
│   └── ws/                       WebSocket 客户端与心跳
├── data/
│   ├── models/                   15 个数据模型（纯 DTO）
│   └── repositories/             7 个仓储：auth / activity / leaderboard / friend / message / goal / badge
└── features/                     按业务域拆分，域内 pages/ + providers/（+ widgets/）
    ├── auth/                     登录、注册
    ├── home/                     首页（含 widgets/ 6 个区块组件）、底部导航壳 main_shell
    ├── activity/                 运动列表、开始运动（start_run）、跑步结果、详情 + widgets/track_map（轨迹地图）
    ├── leaderboard/              排行榜
    ├── friends/                  好友、搜索、聊天
    ├── goals/                    运动目标
    ├── badges/                   勋章
    ├── notifications/            通知聚合页（好友申请 + 未读消息 + 近期勋章 + 已达成目标）
    └── profile/                  个人中心
```

已注册路由：`/splash` `/login` `/register` `/home` `/leaderboard` `/friends` `/profile`
`/activity` `/start-run` `/run-result` `/activity/:id` `/chat/:friendId` `/friends/search`
`/goals` `/badges` `/notifications`。

## 设计系统

- 颜色、字号、间距、圆角、阴影全部走 token：`AppColors` / `AppFontSize` / `AppSpacing` / `AppRadius` / `AppShadows` / `AppFontWeight`。
- 共享原子组件在 `lib/core/widgets/`，可直接单文件 import，也可 `import '.../core/widgets/app_widgets.dart';` 一次性引入：
  `AppMetricText`、`AppProgressRing`、`AppMiniBarChart`、`AppDeltaChip`、`AppEmptyHint`、
  `AppDashboardCard`、`AppTextAction`、`AppCard`、`AppChip`、`AppSectionTitle` 等。
- 首页按 `design/home_spec.png` 规格拆分为 `lib/features/home/widgets/`：
  `home_top_bar` / `home_hero` / `home_today_stats` / `home_weekly_volume` / `home_goal_section` / `home_activity_list`。

编写新页面时请遵守：**不写裸 `Color(0x...)`、不写裸 `fontSize: <数字>`**，一律用上面的 token。

## 运行方式

```bash
flutter pub get

# 桌面/Web（默认连本机后端 http://localhost:8080）
flutter run

# Android 模拟器会自动改用 http://10.0.2.2:8080
# 真机 / 局域网调试：显式指定后端地址
flutter run --dart-define=API_BASE_URL=http://<局域网IP>:8080
```

API 地址优先级见 `lib/core/config/app_config.dart`：
`--dart-define=API_BASE_URL` 覆盖 > 平台默认（Web/桌面 `http://localhost:8080`、Android 模拟器 `http://10.0.2.2:8080`）。

后端启动方式见 [`../campus-run-backend/README.md`](../campus-run-backend/README.md)。

## 测试与静态检查

```bash
flutter test        # 单元/组件测试
flutter analyze     # 静态检查
```

目前 `test/widget_test.dart` 只有 2 个 `Validators` 用例（手机号、密码校验），业务页面与
provider 层测试尚未补齐。

### ⚠️ 无网络环境注意

本机 Flutter 包装脚本 `flutter`（`C:\dev\flutter\bin\flutter.bat`）在没有网络时会卡在
git version check（`git fetch --tags` 访问 github.com）而不返回。此时静态检查直接用原始 Dart SDK：

```powershell
C:\dev\flutter\bin\cache\dart-sdk\bin\dart.exe analyze .
```

（`dart analyze` 会启动 analysis server 子进程，受限沙箱下可能被拒绝；普通桌面环境可用。
`flutter pub get` / `flutter run` 仍需联网或已预热过的 pub cache。）

## 设计资料

| 位置 | 内容 |
|------|------|
| `campus-run-app/design/home_spec.png` | 首页信息架构优化规格板（组件拆分与 token 取值的依据） |
| `campus-run-app/design/home_loaded.png` | 首页数据态效果图 |
| `campus-run-app/design/home_empty.png` | 首页空态效果图 |
| `前端页面示例/`（仓库根目录） | 4 张 UI 示例：`规格说明板.png`、`页面 1.png`、`首页 · 数据态.png`、`首页 · 空态.png` |
| `flutter-design/flutter_ui/`（仓库根目录） | 设计稿导出的 Flutter 参考工程（字体、SVG 素材、原始 Dart 稿），**仅作参考，不是生产代码** |

以上 PNG 与设计工程是**设计资产，必须可提交**，不要加入 `.gitignore`。

## 已实现要点

- 统一设计系统与共享原子组件（`core/theme` token + `core/widgets`，barrel 出口 `app_widgets.dart`）。
- 首页按 `design/home_spec.png` 拆分出 6 个区块组件（`features/home/widgets/`）。
- 新增通知页 `/notifications`：前端聚合好友申请、未读聊天消息、近 7 天勋章、已达成目标，
  红点统一由 `hasNotificationsProvider`（`features/notifications/providers/notifications_provider.dart`）派生，
  无需后端新增接口。
- 消息已读回执适配：`data/models/chat_message.dart` 的 `readAt` 字段，
  聊天页 `_readIds` 集合；WebSocket 类型 `read_receipt` 已在 `core/ws/ws_message.dart` 声明。

## 已知限制 / TODO

- **测试覆盖薄弱**：仅 `test/widget_test.dart` 2 个用例，features/providers 层无测试。
- **首页天气为占位文案**：后端暂无天气接口。
- **通知未读数来自前端聚合**：后端暂无未读数接口，红点由 `hasNotificationsProvider` 依据
  好友申请 / 未读消息 / 近 7 天勋章 / 已达成目标派生（见 `lib/features/notifications/providers/notifications_provider.dart`）。
- **多端会话同步未实现**：后端为单端在线，多设备同时登录不保证消息一致。
- **消息无富媒体**：仅文本消息，图片/语音等未实现。
- **管理员无前端界面**：围栏管理目前只有后端接口，需用 HTTP 工具调用。
