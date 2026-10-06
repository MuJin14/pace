# 发版流程（App + 后端）

## 一、App 发新版（一条命令）

```powershell
# 1. 升版本号（必须做！更新检查靠比对版本号）
#    编辑 campus-run-app/pubspec.yaml 的 version: 1.2.0+3

# 2. 构建（中文路径必须用 subst，且必须与构建同一条命令）
subst P: 'C:\Users\沐瑾\Desktop\project\campus-run-app'
cd P:\
flutter build apk --release --dart-define=API_BASE_URL=http://122.51.191.145:8080

# 3. 发布（上传 APK + 写 version.json + 自动验证）
powershell -ExecutionPolicy Bypass -File campus-run-backend\release-apk.ps1 `
    -Password '<ssh密码>' -Version '1.2.0' -Changelog '1. 修复…… 2. 新增……'
```

**整个过程不需要重建后端镜像**（约 2 分钟，主要是上传 54MB）。

### release-apk.ps1 做了什么

1. 定位 APK（优先用 `build/app/outputs/.../app-release.apk`，永远是最新的）
2. 算 SHA256，生成 `version.json`
3. 上传到服务器 `apk/staging/`
4. **原子替换** `campus-run.apk` + `version.json`（`mv` 同文件系统是原子的，
   下载中的用户不会拿到半个文件）
5. `chmod 644`（容器以 `app`(uid 999) 运行，600 会读不到 → 表现为下载 404）
6. 验证：容器内可读 + 版本接口 `apkReady=true` 且版本号正确 + 下载接口 HTTP 200
7. **任何一步失败就 `exit 1`**，绝不谎报成功

### 为什么版本元数据放在 version.json 而不是配置项

配置项来自 compose 的 `environment`，**改它会让 compose 重建容器**（8 分钟重新编译）。
而发一个新版本只是「换一个 APK 文件」。

`version.json` 由服务端**每次请求实时读取**，所以发版是**秒级生效、零重启**：

```json
{
  "latest": "1.2.0",
  "minSupported": "",
  "changelog": "1. 修复…\n2. 新增…",
  "sha256": "EFBA7308…",
  "releasedAt": "2026-10-05 01:22:44"
}
```

- `latest` 留空 = 不提示更新（接口仍可用）
- `minSupported` 非空且比它旧 → **强制更新**（用于修复严重缺陷，不给「稍后」）

---

## 二、后端部署

```powershell
powershell -ExecutionPolicy Bypass -File campus-run-backend\deploy-server.ps1 `
    -Password '<ssh密码>'
```

约 8 分钟（Docker 内跑 `mvn package`）。

### ⚠️ 服务器上的 compose 文件是**手工维护的，不会被部署覆盖**

`deploy-server.ps1` 只上传 `pom.xml` + 两个模块的 `src`。
服务器 `docker-compose.deploy.yml` 含 `CF_API_TOKEN` / 证书挂载等生产专属内容，
**刻意不从仓库覆盖**。

**这意味着：往 repo 的 compose 里加了新的 volume/env，必须手工同步到服务器**，
否则表现为「代码是新的，但配置没生效」——我因此踩过一次：
`APP_VERSION_APK_PATH` 在容器里是空串，版本接口一直返回「没有新版本」。

同步方式（示例：加 APK 挂载 + 环境变量）：

```bash
cd /home/ubuntu/campus-run-backend
cp -f docker-compose.deploy.yml docker-compose.deploy.yml.bak-$(date +%s)
python3 - <<'PY'
import io
p = 'docker-compose.deploy.yml'
s = io.open(p, encoding='utf-8').read()
old = "      UPLOAD_DIR: /app/uploads\n"
add = (old +
       "      APP_VERSION_APK_PATH: /app/apk/campus-run.apk\n")
s = s.replace(old, add, 1)
s = s.replace("    volumes:\n      - upload-data:/app/uploads\n",
              "    volumes:\n      - upload-data:/app/uploads\n"
              "      - ./apk:/app/apk:ro\n", 1)
io.open(p, 'w', encoding='utf-8', newline='\n').write(s)
PY
sudo docker compose -f docker-compose.deploy.yml up -d --no-build app   # 不要 --build
```

> `--no-build` 很关键：只改挂载/环境变量时不该重新编译镜像。

---

## 三、踩过的坑（改脚本前先读）

### 1. `Set-SCPItem -Destination` 是**目录**，不是文件路径

传 `"$dir/campus-run.apk"` 会得到：

```
scp: /home/ubuntu/campus-run-backend/apk/campus-run.apk: Not a directory
```

正确做法：上传到 `staging/` 目录，再用 `mv` 放进最终位置（顺带获得原子性）。

### 2. Posh-SSH 不保证保留本地文件名

直接传给目录时，`version.json` 曾落地成 `campus-run-version.json`
（它把源文件名前缀拼了上去），导致服务端读不到该文件 → `apkReady=false`。
所以现在统一走 staging + `for f in staging/*.json` 规范化。

### 3. PowerShell 5.1：`Write-Host` 的输出会进函数的 return 值

```powershell
function Invoke-Remote($cmd) {
    Write-Host "..."          # ← 这行也进了 pipeline！
    return [int]$r.ExitStatus # → 调用方拿到 Object[]
}
$st = Invoke-Remote '...'
[int]$st   # ❌ Cannot convert the System.Object[] value to type System.Int32
```

**而且更隐蔽**：`if ($st -ne 0)` 在 `$st` 是数组时**恒为 false**，
于是「命令失败」被当成成功 —— 我因此让脚本在失败时报了 `RELEASE DONE`。

修法：函数返回 **hashtable**（`@{ Exit = ...; Output = ... }`），
调用方取 `$r.Exit`。

### 4. 别让脚本在失败时报成功

最初的 `finally` 里无条件打印 `RELEASE DONE`。
现在 `catch` 里置 `$failed = $true`，`finally` 只负责关连接，
最后 `if ($failed) { exit 1 }`。

---

## 四、客户端侧的行为

| 场景 | 表现 |
|---|---|
| 服务端 `latest` 为空 | 不提示（正常） |
| 服务端版本 ≤ 本机版本 | 不提示 |
| 服务端版本 > 本机且 `apkReady=true` | 弹「发现新版本」，可下载 |
| 服务端版本 > 本机但 `apkReady=false` | **不提示**（避免用户点下载拿到 404） |
| 本机版本 < `minSupported` | 弹强制更新，**没有「稍后」按钮** |

下载完成后由**系统安装器**接管 —— Android 8.0 起禁止静默自安装，
首次还需在系统设置里允许「安装未知应用」。这一步无法绕过（微信、淘宝同样）。

**站点**：`GET /api/v1/app/version` 与 `/download` 都是**免登录**的
（更新提示不该被登录拦住）。


## 「有新版本却不提示更新」的两个原因（2026-10-05）

用户反馈：「为什么到了新版本没有自动更新呢，换句话说之前也没有」。

抽查发现服务端与客户端的**判定逻辑都是对的**（版本接口返回 `apkReady=true`、
`isVersionNewer` 的单测也全绿），问题出在**调用位置**和**弹窗 context** 上。
两个原因叠加，且都属于「静默失败」。

### 原因一：检查被卡在登录之后

`_checkUpdate` 原先写在 `MainShell.initState` 里，而 MainShell 挂在
登录后的 `StatefulShellRoute` 上：

```
启动 → 未登录 → 登录页 → 登录成功 → 主界面 → 才会检查更新
```

**没登录就永远不知道有新版本。** 而版本接口本身是公开的
（不带 token 也返回 200），根本不需要登录态。

**修法**：把检查提到应用级（根组件 `lib/app.dart`），
与登录状态、当前路由完全解耦。

### 原因二（更隐蔽）：弹窗 context 用错了，而且异常被吞掉

```dart
final ctx = scaffoldMessengerKey.currentContext;   // 错
await UpdateDialog.show(ctx, info);
```

`ScaffoldMessenger` 挂在 **Navigator 之上**，它的 context 里没有 Navigator：

```
Navigator operation requested with a context that does not include a Navigator
```

这个异常被 `_checkForUpdate` 的 catch-all 吞掉，只在日志里留一行
「检查更新异常（已忽略）」。

**也就是说：更新弹窗从来就没有弹出来过。**
即使登录了、检查通过了，最后这一步也必然失败。

**修法**：改用属于 Navigator 的 context ——
`_router.routerDelegate.navigatorKey.currentContext`。
（`MaterialApp.router` 不接受 `navigatorKey` 参数，key 由 GoRouter 自己持有。）

### 测试

新增 `test/update_check_placement_test.dart`，用真实 `dioProvider`
（完整拦截器链）+ 捕获型 adapter，断言：

- 未登录（停在启动页/登录页）**也会**请求 `/api/v1/app/version`；
- 请求方法是 GET；
- 一次进程只请求一次；
- 服务端有更新时**真的弹出**更新对话框。

验证有效性：去掉应用级的调用后，4 个用例全部失败。

⚠️ 写这个测试时踩到一个坑：`PackageInfo.fromPlatform()` 在测试环境抛
`MissingPluginException`，而 `_checkForUpdate` 外层是 catch-all ——
异常被吞掉，版本请求根本发不出去，测试会**假通过**（断言「没请求」时）。
必须 mock 掉 `dev.fluttercommunity.plus/package_info` 这个 channel。

⚠️ 另一个坑：原来用 `static bool _updateCheckedThisSession` 做「一次进程只查一次」。
**static 状态在 widget 测试里会跨用例泄漏** —— 第一个用例置为 true 后，
后续用例全被跳过（4 个用例只过了 1 个）。改用 `NotifierProvider` 承载，
既让每个测试容器天然独立，语义也更正确（这本来就是一次性的进程级动作）。


## 服务端主动下发更新信号（2026-10-05）

用户提问：「用服务器给所有不是最新版本的弹出一个新版本提醒可以做到吗」。

**能，但有一个绕不过的前提**：服务端无法让 **1.7.2 及更早**的客户端弹窗 ——
那些版本里弹窗代码本身是坏的（`showDialog` 用了没有 Navigator 的 context），
服务端再怎么发信号，客户端也没有能把它显示出来的代码。
所以这套机制**从 1.7.3 起生效**。

### 为什么不再只用「客户端主动查版本」

原方案是 App 启动时查一次 `/api/v1/app/version`。它的致命弱点是
**要不要提示完全取决于客户端记不记得去查** —— 实际就出了事故：
检查写在登录后的主界面里，没登录的用户永远不知道有新版本。

### 现在的机制

服务端在**每一个 `/api/` 响应**上附带：

| 响应头 | 含义 |
|---|---|
| `X-App-Latest` | 当前最新版本号 |
| `X-App-Min-Supported` | 强制更新下限（仅当 version.json 配了） |
| `X-App-Update-Required` | `true` 表示该客户端必须更新 |

客户端在**每一个请求**上附带：

| 请求头 | 含义 |
|---|---|
| `X-App-Version` | App 自身版本号 |

于是：
- 只要 App 还连着服务器（能登录、能刷列表），**就一定会收到更新信号**，不再依赖它记得去查；
- **零额外请求** —— 挂在已有请求上，不增加流量与延迟；
- 策略由服务端决定：改 `version.json` 即时生效，不用发版。

### 强制更新

把 `version.json` 的 `minSupported` 设为某个版本，低于它的客户端会：

1. 收到 **HTTP 426 Upgrade Required**（响应体沿用 `Result` 结构，`code=426`）；
2. 响应头带 `X-App-Update-Required: true`；
3. 客户端**隐藏「稍后」按钮**，只能更新。

实测（临时设置 `minSupported=1.7.3` 后）：

```
X-App-Version: 1.7.2  ->  HTTP 426   要求强制更新=True
X-App-Version: 1.7.3  ->  HTTP 200   要求强制更新=False
```

**平时保持 `minSupported: ""`（不强制）**，只有出现必须修复的严重问题时才设。

### 几个刻意的设计选择

- **不复用 401**：那会让客户端走进「刷新令牌」流程，拿一个假错误去换 token，
  把问题复杂化。426 是 HTTP 标准里语义最贴合的。
- **下载接口不包装**：54MB 的文件流不该被额外逻辑包裹；
  而且下载它本来就是为了更新，版本信号没有意义。
- **不带 `X-App-Version` 的请求不做任何拦截**：旧客户端、浏览器、脚本
  行为与改动前完全一致，所以这个改动对线上是安全的。
- **版本比较规则与客户端 `isVersionNewer` 完全一致**：两边规则不同会出现
  「服务端要求更新、客户端认为自己已经最新」的僵局。

### 顺手修掉的一个 bug

`UpdateDialog` 里判断「是否强制更新」原本写的是：

```dart
info.minSupported.isNotEmpty && isVersionNewer(info.latest, info.minSupported)
```

**判断对象错了**：它比较的是「服务端最新版」与「服务端下限」，
完全没看用户本机版本。只要 `minSupported` 一配上，
**包括已经是最新版的用户在内，所有人都看不到「稍后」**。
现在改为与本机版本比较。

### 两个实现上的坑

1. **过滤器不能做成 Spring Bean**。最初标 `@Component`，Spring Boot 会把它
   自动注册为 servlet filter，于是每个 `@WebMvcTest` 切片测试都要能构造它 ——
   而切片测试不加载 `AppVersionStore`，**67 个测试 `ApplicationContext` 加载失败**。
   改成 `SecurityConfig` 里的 `@Bean` 也一样。最终方案：
   直接 `new` 进 Security 过滤器链，并把依赖收窄成 `AppVersionProvider`
   函数式接口，`SecurityConfig` 用 `ObjectProvider` 取它，
   切片测试取不到就降级为「不发版本头」——一个测试都不用改。
   **教训：切片测试里取不到的依赖，不要用来构造一个必须存在的 Bean。**

2. **缓存节流破坏了「立即生效」**。给 `AppVersionStore` 加了「1 秒内不重复 stat」
   的节流，结果发版脚本刚写完 `version.json`，紧接着的请求仍读到旧值
   （测试里直接暴露成两个用例失败）。要的就是立即生效，`stat` 本身足够便宜，
   不值得用正确性去换这点开销。现在按 `mtime + size` 判断，无节流。


## 「更新弹窗从来没有出现过」——根因与修复（1.9.3）

### 现象

用户反馈：**「从实装这个功能开始就没见过一个更新弹窗」**。

而后端完全正常：`GET /api/v1/app/version` 返回 `latest: 1.9.2`，
带 `X-App-Version: 1.7.0` 请求时也正确回带 `X-App-Latest: 1.9.2`。

### 根因（三层，每一层都静默）

**① 插件从未被注册进 Android 构建**

`package_info_plus` 在 `pubspec.yaml` 里、也在 pub 缓存里、`pubspec.lock`
也解析到了 9.0.1。但 Flutter 的插件解析文件 `.flutter-plugins-dependencies`
的 `android` 段里**没有它**：

```
android: device_info_plus
android: flutter_local_notifications
android: flutter_plugin_android_lifecycle
android: flutter_secure_storage
android: geolocator_android
android: image_picker_android
android: path_provider_android
android: shared_preferences_android
android: vibration
```

生成的 `GeneratedPluginRegistrant.java` 自然也没有它。

**为什么**：`.flutter-plugins-dependencies` 由 `flutter pub get` 生成，
而本项目的构建命令一直带 **`--no-pub`**（本机 flutter 包装脚本在无网络时
会卡在 `git fetch --tags`，所以加了它）—— 于是那份文件停留在
`package_info_plus` 被加进 pubspec **之前**的版本，插件解析从未更新。

**② 读版本失败，但上游两处都静默**

```dart
// app_update_service.dart（旧）
Future<String> currentVersion() async {
  final info = await PackageInfo.fromPlatform();  // ← MissingPluginException
  return info.version;
}
```

- `_checkForUpdate` 外层是 catch-all：`debugPrint('...（已忽略）')`；
- `VersionSignalInterceptor` 读不到版本时 `return`，注释写着「不猜」。

于是：**版本号永远是 null → 更新检查直接放弃 → 弹窗从不出现 →
日志里一个字都没有。**

**③ 所有测试都是绿的，因为测试 mock 掉了插件**

```dart
// update_check_placement_test.dart（旧）
const MethodChannel('dev.fluttercommunity.plus/package_info')  // ← mock
```

注释里甚至写着「必须把这个 channel mock 掉，否则异常被吞掉、测试变成假通过」——
**而线上正是栽在这里**。测试 mock 掉的恰好是故障点。

### 修复

**放弃 `package_info_plus`，改用自建原生桥。**

补上 `pub get` 后插件确实被注册了，但 9.0.1 的 Kotlin 代码要求
Kotlin 2.x，而本项目是 1.8.22 → 直接编译失败。升级 Kotlin 会牵动
整个 Gradle 构建（本项目在这上面吃过亏），风险远大于收益。

而这件事只需要读一个字符串，原生三行就够：

```kotlin
// MainActivity.appVersion()
val info = packageManager.getPackageInfo(packageName, 0)
"${info.versionName}+${info.longVersionCode}"
```

Dart 侧 `AppVersion.read()` 负责剥掉 `+构建号`（保留它会让版本比较的
第三段解析失败）、缓存、以及在失败时**留下明确日志**。

顺带也消除了「构建期依赖插件解析状态」这类隐患 —— 那种依赖一旦断裂
就是这样一声不响。

### 测试

新增 `test/native_app_version_test.dart`（7 个用例），**直接测原生桥**：

- `1.9.3+37` → `1.9.3`（剥构建号）
- 空串 / null / channel 抛异常 → 空串且不崩
- 缓存生效（第二次不再询问原生）

其中一条用例暴露了同类问题：`Platform.isAndroid` 在单元测试里恒为 false，
`read()` 会被短路成空串、**根本不碰 channel** —— 又是「测试绕过真实路径」。
为此加了 `@visibleForTesting debugForceSupported` 开关。

### 教训

> **静默失败 + 测试 mock 掉故障点 = 一个永远查不出来的 bug。**

三个条件缺一不可，而它们在这件事上同时成立了。以后遇到
「功能装了但用户说没效果」，优先检查：
1. 该功能的依赖是否**真的进了构建产物**（不是「在 pubspec 里」就算）；
2. 失败路径是否**静默**；
3. 测试是否 mock 掉了**唯一会失败的那一环**。


## 更新提醒改为「右上角通知」（1.10.0）

### 改动

从「启动检查 → 直接弹窗」改成「**放进右上角通知**」：

```
有新版 → 铃铛出现红点 → 点进通知页 → 看到「发现新版本 x.y.z」
      → 点这一条 → 弹更新对话框
```

### 为什么改

原实现在冷启动时弹「要更新吗」，实测两个问题：

1. **打扰** —— 用户此刻往往只想看一眼步数，突然被问要不要更新；
2. **更容易被误关掉** —— 用户条件反射点「稍后」，之后**再也没有入口**，
   更新提示等于彻底失效。

这两个问题叠加的结果就是「**装了更新提示，但永远没人更新**」——
比不装还糟。

改成通知入口后：不打扰，且**入口常驻在通知页里**，不会被误关掉。

### 例外：强制更新仍然直接弹窗

低于服务端下发的 `minSupported` 时，继续用旧版本会出问题
（接口不兼容等），不能等用户自己发现。此时仍然立即弹窗且不可关闭。

判断集中在 `_AppState._isMandatory`：

```dart
bool _isMandatory(AppVersionInfo info, String current) {
  if (info.minSupported.isEmpty || current.isEmpty) return false;
  return isVersionNewer(info.minSupported, current);
}
```

> ⚠️ 这个方法里的 `current.isEmpty` 很关键：读不到本机版本时**不能**判定为强制，
> 否则会把「读不到版本号」变成「强制所有人更新」——一个读取故障直接升级成
> 全量强制更新事故。

### 实现

| 层 | 文件 | 职责 |
|---|---|---|
| 状态 | `core/update/pending_update_provider.dart` | 「有一个待安装的新版本」这个事实 |
| 聚合 | `features/notifications/providers/notifications_provider.dart` | 新增 `AppNotificationType.appUpdate`，**排在最前** |
| 展示 | `features/notifications/pages/notifications_page.dart` | 该条目**不带 route**，点击就地弹对话框 |

`pending_update_provider` 由两条路径写入（`app.dart`）：

- 启动检查 `_checkForUpdate`；
- 服务端主动下发信号 `VersionSignalInterceptor.onUpdate` → `_promptForVersion`。

两条路径都遵循同一规则：普通更新只记录，强制更新才立即弹窗。

### 测试

`test/update_notification_test.dart`（10 个用例）守的是**入口确实会出现**：

- 有新版本时通知里出现该条目、排在最前、不带 route；
- 强制更新时文案说清「必须」；
- 铃铛红点会亮；
- 同一版本重复记录不产生额外重建；
- 没有新版本时不出条目。

为什么专门守这个：**如果 `pendingUpdateProvider` 没被写入，通知里就没有这一条，
而界面上看不出任何异常** —— 表现又会是「更新提示没了」。
这正是上一轮（更新弹窗从未出现）的同一种失败模式。

`test/update_check_placement_test.dart` 也相应更新：
原来的「服务端有更新时会真的弹出更新对话框」改为
「**有新版本时不直接弹窗**」，另加一条「**强制更新时仍然立即弹窗**」。

### 顺带修掉一个测试盲区

`update_check_placement_test` 里始终有个隐患：`Platform.isAndroid` 在单元测试里
恒为 false，`AppVersion.read()` 会被短路成空串、**根本不碰 channel** ——
于是那些用例测的是「空实现」，看起来全绿。

现在统一用 `AppVersion.debugForceSupported = true` 显式打开。
（同一个盲区在 `native_app_version_test.dart` 里也踩过一次。）


## 陷阱：空版本号会被当成「0.0.0」（1.10.1）

### 现象

读不到本机版本号时，**所有用户都会被告知「发现新版本」**。

### 根因

`isVersionNewer` 按 `.` 切分并取每段的数字前缀：

```dart
int parse(String s, int i) {
  final parts = s.split('.');
  if (i >= parts.length) return 0;      // ← 空串在这里返回 0
  ...
}
```

于是：

```
isVersionNewer('9.9.9', '')  ==  true
```

因为空串切分后每一段都不存在 → 全部当 0 → 任何版本都比它"新"。

`checkForUpdate` 原来直接拿它比较：

```dart
if (!isVersionNewer(info.latest, currentVersion)) return null;  // 空版本时误判为有新版本
```

### 后果

只要 `AppVersion.read()` 返回空串（原生桥异常、ROM 限制、channel 不可用），
**一个读取故障就升级成全量误报** —— 所有用户被通知「有新版本」，
而他们可能已经是最新版。

### 修复

在 `checkForUpdate` 入口加守卫，把「**不知道版本**」和「**比它新**」区分开：

```dart
if (currentVersion.isEmpty) {
  debugPrint('[update] 本机版本号为空，跳过更新检查（不能拿空版本去比较）');
  return null;
}
```

### 教训

> **「不知道」不能被当成一个值参与比较。**

`AppVersion.read()` 用空串表达「读不到」，而 `isVersionNewer` 把空串当成
「版本 0」—— 两个各自合理的约定撞在一起，产出了一个语义完全错误的结果。
这类 bug 的特点是**单看任何一边都挑不出毛病**。

同类隐患已在两处显式防住：
- `checkForUpdate`：空版本直接放弃（本次修复）；
- `_AppState._isMandatory`：空版本不判定为强制更新。

### 测试

新增 `test/update_entry_e2e_test.dart`，**从启动开始走完整链路**：

1. 启动 → 版本接口被请求 → 通知聚合里出现「发现新版本」→ 铃铛亮起；
2. 已是最新版 → 不出现该条目；
3. **读不到版本号 → 不出现该条目**（就是上面这个 bug 的回归防线）。

与 `update_notification_test.dart` 的分工：
那一组直接往 provider 里塞数据，测「塞进去之后能否正确展示」；
这一组测「**它到底会不会被塞进去**」—— 后者失败时界面上没有任何异常，
必须单独守住。


## 版本号规则：小版本不出现两位数（2.0 起生效）

### 规则

**次版本号（第二位）只用 0-9。** 需要第 10 次功能迭代时，
**直接进大版本**（`1.9.x` -> `2.0.0`），不要写 `1.10.0`。

```
1.7.x -> 1.8.0 -> 1.9.0 -> 1.9.1 ... 1.9.9
                                        |
                                        v
                                      2.0.0   （而不是 1.10.0）
```

### 为什么

版本号是**给人看的**，不是给机器排序的：

- 界面上 `1.10.0` 与 `1.1.0` 视觉上只差一个字符，用户容易看错、也难记；
- 「1.9 之后是 1.10」是程序员的直觉，不是普遍直觉 ——
  大多数人的直觉是「1.9 之后该到 2.0 了」；
- 大版本号能承载「这次更新比较重要」的语义。本次从 1.9.x 直接进 2.0，
  就是因为这一轮改动量确实到了一个量级（见下方 2.0.0 的说明）。

### ⚠️ 澄清：这不是技术限制

曾经怀疑两位次版本号会让版本比较出错（以为 `1.10.0` 会被解析成 `1.1.0`），
**实测证明是错的**：解析用的是 `^\d+`，匹配完整数字串。

```dart
1.10.0 -> [1, 10, 0]      // 正确
1.9.0  -> [1,  9, 0]
isVersionNewer('1.10.0', '1.9.0') == true   // 正确
```

所以这条规则**纯粹是产品与命名习惯上的取舍**，不是为了避免 bug。
把它写下来的目的是：以后发版时不必重新讨论一次。

### 执行方式

发版脚本 `release-apk.ps1 -Version` 接受任意版本字符串，
遵守规则靠自觉。发版前对照本节的递增表确认一次即可。
