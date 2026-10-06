# 真机调试与上机验收

Android 侧的环境、已知坑与上机验收清单。

## 真机调试（Android）
前置条件已核实：Flutter 3.29.3、Android SDK 36.1.0、Android Studio 2025.3.2 均就绪。
**但 `build/app` 从不存在 —— 本项目从未构建过 Android 包**，首次构建需要联网拉 Gradle 依赖。

### 推荐方式：adb reverse（绕开防火墙与 IP 变动）

Windows 防火墙 + `Public` 网络类型默认**阻止手机访问 PC 的 8080**，
而 `adb reverse` 把连接逆向隧道到 USB 上，**不经过网络**，因此：

- 不需要动防火墙、不需要固定 IP、不需要手机与 PC 同网段
- App 里连 `http://127.0.0.1:8080` 即可（Android 默认值即为此）。
  ⚠️ **必须是 `127.0.0.1`，不能写 `localhost`** —— 详见下方「真机连接」小节，写错会表现为 App 报网络错误、而 curl 却能通。

```bash
# 1. 手机开启开发者选项 + USB 调试，插上 USB（选"文件传输"模式）
C:\Android\Sdk\platform-tools\adb.exe devices          # 应看到 device（不是 unauthorized）
C:\Android\Sdk\platform-tools\adb.exe reverse tcp:8080 tcp:8080

# 2. 启动后端（本机）
cd campus-run-backend\campus-run-server
java -jar target\campus-run-server-1.0.0-SNAPSHOT.jar

# 3. 跑 App（真机默认就是 localhost，无需额外参数）
cd campus-run-app
flutter run -d <设备id>
```

### 备选方式：局域网直连

需要额外放行防火墙入站 8080（**需要管理员权限**），然后用 WLAN IP：

```powershell
New-NetFirewallRule -DisplayName "campus-run 8080" -Direction Inbound -Protocol TCP -LocalPort 8080 -Action Allow
```

```bash
flutter run --dart-define=API_BASE_URL=http://<PC的WLAN IP>:8080
```

> ⚠️ **`PUBLIC_BASE_URL` 决定头像 URL 的主机名**。用 adb reverse 时填 `http://localhost:8080`；
> 局域网直连时填 `http://<WLAN IP>:8080`，否则手机拿到的头像 URL 指向它自己、加载失败。

### 首次构建的已知坑

- `maven.google.com` 在国内常超时（`flutter doctor` 已提示网络错误）。
  首次 `flutter build apk` 若卡住或失败，配置 Gradle 国内镜像
  （`android/build.gradle` 的 `repositories` 换成阿里云 `maven.aliyun.com/repository/google` 等）。
- 首次构建可能要 10-20 分钟，属正常。

### 上机验收清单（按重要性排序）

1. **切后台/锁屏后轨迹是否连续**（本次真机的核心目的，此前只做过代码层验证）。
   注意把定位权限设为「始终允许」，并在 MIUI/EMUI 等系统里关闭该 App 的省电限制，
   否则前台服务会被杀 —— 那是系统行为，不是代码问题。
2. **杀掉 App 再进**：应提示「已恢复上次未完成的运动」，距离/时长延续。
3. **距离准不准**：与已知路线（如操场圈数）比对，偏差应在几个百分点内。
4. **不要出现「不计入成绩」**：跑完看结果页，不应被判作弊（这是上一轮修掉的主要缺陷）。
5. 上传失败时草稿应保留并提示可重试。

### ⚠️ 真机连接：Android 侧**必须用 `127.0.0.1`，不能用 `localhost`**

`AppConfig.baseUrl` 在 Android 上返回 `http://127.0.0.1:8080`（**不是 `localhost`**）。

原因：真机通过 `adb reverse` 连后端时，**Dart 的 HTTP 客户端解析 `localhost` 会优先走 IPv6（`::1`），
而 `adb reverse` 建立的是 IPv4 隧道** —— 请求发不出去，App 停在启动页报「网络连接失败」。

**这个坑极易误判**：从手机 `curl localhost:8080` 是**通的**（curl 会自动回退到 IPv4），
于是很容易得出「隧道没问题、肯定是代码 bug」的错误结论，然后在错误方向排查很久。
判断方法：`adb shell curl` 通但 App 不通时，优先怀疑地址族解析差异。

### 国内 ROM 定位：`forceLocationManager: true` 是**必需项**

`AndroidSettings(forceLocationManager: true)` **不能省**。

geolocator 默认（`false`）走 Google Play Services：

```java
// geolocator_android FusedLocationClient.isLocationServiceEnabled
LocationServices.getSettingsClient(context)
    .checkLocationSettings(...)
    .addOnCompleteListener((response) -> {
        if (!response.isSuccessful()) {
          listener.onLocationServiceError(ErrorCodes.locationServicesDisabled);
```

国内 ROM 上 GMS 这个调用会失败，插件**直接报「The location service on the device is disabled」**，
而实际上系统定位完全正常（`dumpsys location` 显示 provider 全部 `enabled=true`、
系统 `location_mode=3`、微信/高德都能定位）。

设为 `true` 后改用原生 `LocationManagerClient`，判断条件是
`isProviderEnabled(GPS) || isProviderEnabled(NETWORK)`，**不依赖 GMS**。

配套的两处修复（都是真实缺陷）：
- **不要用 `Geolocator.isLocationServiceEnabled()` 做前置拦截** —— 它同样走 GMS，会误杀正常用户。
  正确做法是**直接尝试获取位置**，用真实结果判断。
- **首个定位点超时给 45 秒**（GPS 冷启动需 30-60 秒，原先 10 秒会把「还在搜星」判成失败）；
  并且**单次流错误不判死**（`cancelOnError: false`），MIUI 偶发报一次错后会自行恢复。

### 网络形态与部署（决定「能不能拿出去跑」）

| 形态 | 手机可达性 | 说明 |
|------|-----------|------|
| `adb reverse` | 仅插 USB 时 | 隧道会随插拔/息屏失效，且 `--list` 仍显示存在，容易误判 |
| 手机热点（手机当 AP） | 热点范围内 | 手机一离开热点就断 |
| 同一 WiFi（宿舍/家用） | 同网段 | 通常可用 |
| **校园网** | ❌ **不可用** | 实测：同 `/17` 网段但 **100% 丢包** —— 开了 **AP 隔离（客户端隔离）**，这是校园网标准安全策略，无管理权限改不了 |
| **公网服务器** | ✅ 随时随地（4G 也行） | **唯一能让 App 拿出去用的形态** |

**结论**：调试期用 `adb reverse`；要「去操场跑」必须部署到公网，见
`campus-run-backend/docs/deploy.md`（通用）与 `docs/deploy-oracle.md`（Oracle 免费层）。

### 服务器地址**运行时可改**（不要只依赖编译期注入）

- 登录页底部与**启动页错误态**都有「修改服务器地址」入口 → `/server-setting`。
- 存储：`lib/core/storage/server_address_storage.dart`（`shared_preferences`）。
- 优先级：本地保存 > 编译期 `--dart-define=API_BASE_URL` > 平台默认值。
- ⚠️ **必须在每次请求前重写 baseUrl**（`BaseUrlInterceptor`）：`BaseOptions.baseUrl`
  在构造 Dio 时就固定了，用户改地址后已存在的 Dio 实例不会自动更新。
- 校验走 `normalizeServerAddress()`（自动补 `http://`、去尾斜杠、挡掉 `http://` 这类伪主机）。

### 路由守卫的**死锁**（曾经很痛，务必保持）

`resolveRedirect`（`lib/core/router/app_router.dart`，已提取为纯函数便于单测）：
网络异常时**必须放行** `/splash`、`/login`、`/server-setting`。

曾经写死 `if (auth.hasError) return '/splash'`，结果是：服务器地址填错或换了网络时，
App 永远停在启动页一个「重试」按钮上，而**改地址的入口恰好在进不去的页面后面** ——
用户完全无法自救，只能卸载重装。回归由 `test/router_guard_test.dart` 固化（11 个用例）。

### 已知未修复：Riverpod `setState() called during build`

真机运行时会打印：

```
══╡ EXCEPTION CAUGHT BY RIVERPOD ╞══
setState() or markNeedsBuild() called during build.
This UncontrolledProviderScope widget cannot be marked as needing to build
  #31 MainShell.build (main_shell.dart:19)   ← ref.watch(hasNotificationsProvider)
```

- **触发点**：`MainShell` / `home_top_bar` 在 build 期间 watch
  `hasNotificationsProvider` → `notificationUnreadCountProvider` → `notificationsProvider`
  这条链（后者的 4 个依赖都是异步 provider）。
- **严重性**：据 Riverpod 官方 issue [#4812](https://github.com/rrousselGit/riverpod/issues/4812)，
  该异常抛出后 **`ProviderScheduler` 会永久冻结**，之后所有 provider 更新不再生效
  （相关：[#4781](https://github.com/rrousselGit/riverpod/issues/4781)、
  [#4805](https://github.com/rrousselGit/riverpod/issues/4805)、
  [#4834](https://github.com/rrousselGit/riverpod/issues/4834)）。
  症状是红点/通知偶尔不刷新。
- **当前状态**：**未修复**。试过用「多层派生链 + 异步上游」的合成 widget 测试复现，
  **未能触发** —— 说明它依赖整个 App 与导航时序，不是抽象链就能重现。
  下次处理时建议：先在真机上稳定复现（记录触发前的操作路径），再逐个替换
  `notificationsProvider` 的 4 个依赖做二分定位；不要盲目改 provider 结构。
