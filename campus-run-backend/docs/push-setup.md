# 离线推送配置指南（FCM HTTP v1）

> 目标：**App 完全关闭时，收到好友消息也能在手机通知栏看到。**
>
> 代码已全部实现并测试通过；本文件说明**你需要提供什么**才能让它真的发出通知。
> 没有这些配置时系统不会报错，只会走 `LoggingPushSender` 把通知内容写进日志
> （见「验证方式」一节），所以开发阶段也能完整验证链路。

---

## 为什么必须用 FCM HTTP v1

Google 已于 **2024 年停用旧的「服务器密钥 + `/fcm/send`」接口**。
网上绝大多数中文教程仍是旧版，照抄会直接拿到 404 / 401。
本项目用的是 v1：`POST https://fcm.googleapis.com/v1/projects/{projectId}/messages:send`，
鉴权走服务账号 OAuth2（见 `FcmPushSender`）。

---

## 一、你需要准备的东西

| # | 物品 | 从哪来 | 用途 |
|---|------|--------|------|
| 1 | Firebase 项目 | [console.firebase.google.com](https://console.firebase.google.com) 新建 | 推送的总入口 |
| 2 | `google-services.json` | 项目设置 → 你的应用（Android）→ 下载 | 前端初始化，Android 用 |
| 3 | `GoogleService-Info.plist` | 同上，iOS 应用 → 下载 | 前端初始化，iOS 用 |
| 4 | **服务账号 JSON** | 项目设置 → 服务账号 → 生成新的私钥 | **后端发推送用**，含私钥 |
| 5 | Web 推送证书（VAPID 公钥） | 项目设置 → 云消息传递 → 网页配置 → 生成密钥对 | 仅在 Web 上收推送才需要 |

> ⚠️ **第 4 项含私钥，绝不能提交到 git。** 把文件名加进 `.gitignore`。
> 泄露等于任何人都能以你的名义给全体用户发通知。

---

## 二、后端配置

把服务账号 JSON 放到服务器上（例如 `/etc/campus-run/firebase-service-account.json`），然后：

```bash
export PUSH_ENABLED=true
export PUSH_CREDENTIALS=/etc/campus-run/firebase-service-account.json
```

或写进 `application.yml`（**不要提交含真实路径与私钥的版本**）：

```yaml
app:
  push:
    enabled: true
    credentials: /etc/campus-run/firebase-service-account.json
```

启动时会看到：

```
FCM 推送已启用，projectId=your-project-id
```

**若看到 `未配置 app.push.credentials` 或 `读取 FCM 凭证失败`，说明配置没生效**，
此时推送会退化为只写日志。

### 关键行为（已实现，不是待办）

- **对方在线时不推**：App 已通过 WebSocket 显示消息，再弹系统通知是重复打扰。
  只有 `sessionManager.isOnline(receiverId) == false`（App 关闭/挂起）才推。
- **消息先落库再推**：推送失败绝不丢消息。
- **令牌失效自动清理**：FCM 返回 `UNREGISTERED` 时删除该令牌；
  而网络/限流等临时故障**保留**令牌（删错会导致用户永远收不到通知）。
- **推送异常不影响消息发送**：整条链路吞异常并记日志。

---

## 三、前端配置

### Android

1. `google-services.json` 放到 `campus-run-app/android/app/`
2. `android/app/build.gradle` 应用插件：

```gradle
plugins {
    id 'com.google.gms.google-services'
}
```

3. 根 `android/build.gradle`：

```gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.2'
}
```

4. Android 13+ 需要通知权限（已在前端代码里申请）。

### iOS

1. `GoogleService-Info.plist` 放到 `campus-run-app/ios/Runner/`
2. Xcode → Signing & Capabilities → 添加 **Push Notifications** 与 **Background Modes → Remote notifications**
3. 在 Apple Developer 后台创建 APNs Key，上传到 Firebase 控制台
   （项目设置 → 云消息传递 → Apple 应用配置）

### Web（当前演示环境）

1. 项目设置 → 云消息传递 → 网页配置 → 生成密钥对，拿到 **VAPID 公钥**
2. 在 `lib/main.dart` 初始化 FCM 前设置：

```dart
await FirebaseMessaging.instance.getToken(vapidKey: '你的 VAPID 公钥');
```

3. 需要 `web/firebase-messaging-sw.js`（我会在前端实现里一并放好）

---

## 四、验证方式

### 开发阶段（无凭证）

后端会打印完整通知内容，用这个确认「该推的推了、文案对了、跳转参数对了」：

```
[PUSH-DEV] token=***23456789 title="Mujin" body="在吗" data={route=/friends, messageId=7, ...}
推送完成: receiverId=2 设备数=1 成功=0
```

**测试步骤**（已在本地验证通过）：

1. 登录 B 账号，调 `POST /api/v1/device/token` 登记一个假令牌
2. 用 A 账号通过 WebSocket 给 B 发一条消息（B 不在线）
3. 后端日志应出现上面的 `[PUSH-DEV]` 行

### 生产阶段（有凭证）

1. 后端启动日志出现 `FCM 推送已启用，projectId=...`
2. 真机上装 App、登录、切到后台或杀掉进程
3. 另一个账号发消息 → 手机通知栏应弹出「发件人昵称 + 消息预览」
4. 点击通知 → 跳到社区/会话页

---

## 五、常见问题

| 现象 | 原因 | 处理 |
|------|------|------|
| 推送全是 `NOT_CONFIGURED` | 没配 `PUSH_ENABLED` / `PUSH_CREDENTIALS` | 按第二节配置 |
| `获取 FCM access_token 失败 HTTP 400` | 服务账号 JSON 不完整，或缺 `client_email`/`private_key` | 重新生成私钥 |
| `HTTP 404` | projectId 与凭证不匹配 | 确认 JSON 里的 `project_id` |
| 真机收不到但日志显示成功 | APNs 证书/Key 没配（iOS），或没申请通知权限 | 见第三节 |
| 前台收到消息但没弹通知 | **设计如此**：对方在线时不推，避免重复打扰 | 想要前台也弹需另做本地通知 |
| 令牌被反复清理 | 客户端拿的是旧令牌（重装后失效） | 前端每次启动重新 `getToken()` 并上报 |

---

## 六、已知限制

- **对方在线时不推系统通知**。这是刻意的：消息已经通过 WebSocket 显示在 App 里，
  再弹一次是骚扰。如果你希望「前台也弹通知」，那需要在前端加本地通知
  （`flutter_local_notifications`），走的是另一套机制。
- **单实例部署**：推送在业务线程内同步发送。量大时应改为队列 + 重试
  （`PushSender` 已抽象好，替换实现即可）。
- **令牌与账号绑定**：同一台设备换账号登录会改写令牌归属
  （`ON DUPLICATE KEY UPDATE`），登出应调 `DELETE /api/v1/device/token`，
  否则会收到上一个账号的通知 —— 这属于隐私泄露。
