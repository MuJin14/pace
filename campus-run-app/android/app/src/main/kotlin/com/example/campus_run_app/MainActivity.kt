package com.example.campus_run_app

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Flutter 宿主 Activity + 电池优化状态的桥。
 *
 * 这里只提供**平台能力**（查询状态、跳到系统设置），不做业务判断 ——
 * 什么时候提示用户、怎么措辞，都由 Dart 侧决定（那里才好写测试）。
 *
 * ⚠️ 这里**刻意不提供**「启动前台服务保活」：
 * 那需要一条常驻通知，属于对用户的强制打扰，已评估后放弃。
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "campus_run/platform"
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "appVersion" -> {
                        result.success(appVersion())
                    }

                    "isIgnoringBatteryOptimizations" -> {
                        result.success(isIgnoringBatteryOptimizations())
                    }

                    "openBatteryOptimizationSettings" -> {
                        result.success(openBatteryOptimizationSettings())
                    }

                    // 「是否允许安装未知应用」。Android 8.0+ 唤起安装器需要它。
                    // 见 canInstallPackages 的说明。
                    "canInstallPackages" -> {
                        result.success(canInstallPackages())
                    }

                    "openInstallPermissionSettings" -> {
                        result.success(openInstallPermissionSettings())
                    }

                    // 打开外部链接（目前用于「查看 GitHub 仓库 / 发行版」）。
                    //
                    // 为什么不用 url_launcher：见 appVersion() 的说明 ——
                    // 本项目历史上就因为「插件没被注册进构建」而静默失败过。
                    // 打开一个链接只需一个 Intent，不值得为此再引一个插件、
                    // 再承担一次「构建期插件解析」的风险。
                    "openUrl" -> {
                        val url = call.argument<String>("url").orEmpty()
                        result.success(openUrl(url))
                    }

                    else -> result.notImplemented()
                }
            }
    }

    /**
     * 本应用是否被允许安装其他应用（「安装未知应用」开关）。
     *
     * ## 为什么需要这个查询
     *
     * 用户反馈过「更新包下载完了，却没有弹出安装界面」。根因有两层：
     *
     *  1. manifest 里缺 `REQUEST_INSTALL_PACKAGES`（已补）——
     *     没有它，Android 8.0+ 会**静默拒绝**安装意图；
     *  2. 即使声明了权限，**用户仍可能在系统弹窗里点「拒绝」**。
     *     那种情况下安装同样不会发生，而且 open_filex 可能仍返回成功，
     *     界面一片安静 —— 用户只会觉得「点了没反应」。
     *
     * 所以下载完成后先查这个开关：不允许就给出**可操作**的指引，
     * 而不是让用户对着一个没反应的按钮发呆。
     *
     * Android 8.0 以下没有这个概念（安装未知应用是全局设置），返回 true。
     */
    private fun canInstallPackages(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return true
        return packageManager.canRequestPackageInstalls()
    }

    /**
     * 跳到「安装未知应用」授权页。
     *
     * ⚠️ 这个页面是**应用级**的（Android 8.0+），有标准 Intent 可直达；
     * 但部分 ROM 会把它替换成自家页面，甚至跳不过去 —— 那时退回本应用详情页，
     * 让用户自己找，总比什么都不做强。
     */
    private fun openInstallPermissionSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return false
        val intents = listOf(
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES)
                .setData(Uri.parse("package:$packageName")),
            Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES),
            Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS)
                .setData(Uri.parse("package:$packageName")),
        )
        for (intent in intents) {
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            try {
                startActivity(intent)
                return true
            } catch (_: Exception) {
                // 试下一个
            }
        }
        return false
    }

    /**
     * 用系统浏览器打开一个 http/https 链接。
     *
     * ⚠️ 只接受 http/https：如果放任任意 scheme（如 `intent://`、`file://`），
     * 传入一个构造过的字符串就可能拉起别的应用甚至本地文件 —— 这是
     * 常见的 Intent 注入面。这里在原生侧就挡掉。
     *
     * 返回 false 表示没有应用能处理（例如设备上没有浏览器），
     * 由 Dart 侧决定怎么提示，而不是假装成功。
     */
    private fun openUrl(url: String): Boolean {
        if (url.isEmpty()) return false
        val uri = try {
            Uri.parse(url)
        } catch (_: Exception) {
            return false
        }
        val scheme = uri.scheme?.lowercase()
        if (scheme != "http" && scheme != "https") return false

        return try {
            startActivity(
                Intent(Intent.ACTION_VIEW, uri).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            )
            true
        } catch (_: Exception) {
            false
        }
    }

    /**
     * 本应用的版本号，格式与 Dart 侧一致：`版本名+构建号`（如 `1.9.3+37`）。
     *
     * ## 为什么自己读，而不用 package_info_plus
     *
     * 项目里原本用 `package_info_plus`。它在 pubspec 里、也装了下来，
     * 但**从来没有被注册进 Android 构建** —— 因为 `.flutter-plugins-dependencies`
     * 是 `flutter pub get` 生成的，而构建一直带 `--no-pub` 跳过 pub，
     * 那份文件停留在很早以前的版本。于是 `PackageInfo.fromPlatform()` 抛
     * `MissingPluginException`，而它上游两处都是**静默失败**，
     * 结果是**更新弹窗永远不出现、日志里一个字都没有**。
     *
     * 补上 `pub get` 之后插件确实被注册了，但 9.0.1 的 Kotlin 代码要求
     * Kotlin 2.x，而本项目是 1.8.22 —— 直接编译失败。
     * 升级 Kotlin 会牵动整个 Gradle 构建，风险远大于收益。
     *
     * 而这里要做的事只是读一个字符串，原生三行就够了。
     * 顺带还去掉了构建期对插件解析状态的隐式依赖。
     */
    private fun appVersion(): String {
        return try {
            val info = packageManager.getPackageInfo(packageName, 0)
            val name = info.versionName ?: return ""
            val code = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                info.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                info.versionCode.toLong()
            }
            // Dart 侧会自己剥掉 "+" 之后的部分，这里带上更完整
            "$name+$code"
        } catch (e: Exception) {
            // 读不到就返回空串：调用方会安全地跳过更新检查，
            // 而不是拿一个假版本号去比较。
            ""
        }
    }

    /**
     * 本应用是否已被排除在电池优化之外。
     *
     * 国产 ROM 的省电策略比原生更激进：即使有前台服务，被列为「受限制」
     * 时照样会冻结。这个查询在原生 Android 上准确，
     * 在部分国产 ROM 上可能恒为 true —— 所以 Dart 侧只把它当作
     * 「已知未排除」的判据，不做反向判断（与定位服务的处理一致）。
     */
    private fun isIgnoringBatteryOptimizations(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return true
        val pm = getSystemService(Context.POWER_SERVICE) as? PowerManager ?: return true
        return pm.isIgnoringBatteryOptimizations(packageName)
    }

    /**
     * 打开系统的「电池优化」设置列表。
     *
     * ⚠️ 只**打开设置页**，不申请、不改动任何东西 —— 让用户自己决定。
     *
     * 曾经这里用的是 `ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS`（直接弹
     * 「是否允许忽略电池优化」的确认框）。那个更省事，但配合前台服务保活
     * 会让 App 在通知栏常驻一条通知，对用户是强制打扰，已整体放弃。
     *
     * 现在只把用户送到设置页：想设就设，不想设也不影响 App 的任何功能，
     * 只是后台收到消息的及时性差一些。
     */
    private fun openBatteryOptimizationSettings(): Boolean {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) return false
        return try {
            startActivity(Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS))
            true
        } catch (_: Exception) {
            // 个别 ROM 没有这个页面，退回本应用的详情页
            try {
                startActivity(
                    Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS).apply {
                        data = Uri.parse("package:$packageName")
                    }
                )
                true
            } catch (_: Exception) {
                false
            }
        }
    }
}
