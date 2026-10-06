package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.update.AppVersionMetadata;
import com.campusrun.server.update.AppVersionStore;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.core.io.FileSystemResource;
import org.springframework.core.io.Resource;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.util.LinkedHashMap;
import java.util.Map;

/**
 * App 自更新：版本信息 + APK 下载。
 *
 * <p><b>为什么需要它</b>：每次改完都要用户手动重装 APK，老用户会永远停在旧版本。
 * 有了这两个接口，App 启动时比一次版本号，有新版本就提示下载。
 *
 * <p><b>为什么不能让 App 静默安装</b>：Android 8.0 起禁止应用静默自安装，
 * <b>任何</b>方案都必须下载后弹系统安装器让用户点「安装」，
 * 首次还要在系统设置里授权「安装未知应用」。微信、淘宝也是这个流程。
 * 所以这里只负责「把正确的包交给用户」，安装动作由系统完成。
 *
 * <p><b>为什么不用应用商店 SDK</b>：国内无法使用 Google Play，
 * 华为/小米/OPPO 各自一套 SDK，工作量是自建方案的好几倍，
 * 对当前「小范围传播」的规模不划算。
 *
 * <h3>版本元数据放在 version.json，而不是配置项</h3>
 *
 * <p>最初把它做成 {@code app-version.*} 配置项，但有个很实际的缺点：
 * 配置来自 compose 的 {@code environment}，<b>改它会让 compose 重建容器</b>。
 * 而发一个新版本只是「换一个 APK 文件」，不该触发 8 分钟重新编译。
 *
 * <p>现在改为读 {@code <apk 目录>/version.json}，<b>每次请求实时读取</b>
 * （文件很小，且挂载目录本来就是只读静态内容）：
 * 发版 = 上传 APK + 改一个 JSON，<b>秒级生效、零重启</b>。
 *
 * <p>{@code version.json} 格式（文件不存在或字段缺失都能正常工作）：
 * <pre>
 * {
 *   "latest": "1.2.0",
 *   "minSupported": "1.0.0",
 *   "changelog": "1. 修复...\n2. 新增..."
 * }
 * </pre>
 */
@RestController
@RequestMapping("/api/v1/app")
public class AppVersionController {

    private static final Logger log = LoggerFactory.getLogger(AppVersionController.class);

    private final Path apkPath;
    private final String publicBaseUrl;

    /**
     * 版本元数据统一从 {@link AppVersionStore} 取（带 mtime 缓存）。
     *
     * <p>这里曾经自己读一遍 version.json，而 {@code AppVersionHeaderFilter}
     * 也要读一遍 —— 两处各自解析同一个文件，字段规则很容易漂移
     * （比如一边读了 minSupported、另一边忘了）。
     * 现在只有 Store 一处负责读取与解析。
     */
    private final AppVersionStore versionStore;

    public AppVersionController(
            @Value("${app-version.apk-path:}") String apkPath,
            AppVersionStore versionStore,
            @Value("${app.public-base-url:http://localhost:8080}") String publicBaseUrl) {
        this.apkPath = apkPath == null || apkPath.isBlank()
                ? null
                : Paths.get(apkPath).toAbsolutePath().normalize();
        this.versionStore = versionStore;
        this.publicBaseUrl = publicBaseUrl.endsWith("/")
                ? publicBaseUrl.substring(0, publicBaseUrl.length() - 1)
                : publicBaseUrl;
    }

    /**
     * 版本信息（<b>无需登录</b>）。
     *
     * <p>返回体刻意做成「即使没配置也结构完整」：客户端只需判断
     * {@code latest} 是否为空、是否比自己新，不必处理缺字段的情况。
     */
    @GetMapping("/version")
    public Result<Map<String, Object>> version() {
        Map<String, Object> data = new LinkedHashMap<>();

        AppVersionMetadata meta = versionStore.current();
        String latest = meta.latest();
        data.put("latest", latest);
        data.put("minSupported", meta.minSupported());
        data.put("changelog", meta.changelog());

        boolean apkReady = apkPath != null && Files.isReadable(apkPath);
        // 关键：**版本号有了但 APK 还没放好时，客户端不该提示更新** ——
        // 否则用户点了下载拿到 404，体验比不提示更糟。
        data.put("apkReady", apkReady);
        data.put("apkUrl", apkReady ? publicBaseUrl + "/api/v1/app/download" : null);
        if (apkReady) {
            try {
                data.put("apkSizeBytes", Files.size(apkPath));
                // 一并给出 APK 的 sha256，供客户端**续用已下载的安装包**。
                //
                // 背景（用户反馈）：下载完成 → 系统要求授权「安装未知应用」→
                // 用户同意后点「重试」，结果 54MB **又下了一遍**。
                // 客户端要在重试前判断「本地那个包是不是就是这一版」，就必须
                // 有可信的校验值；只比文件大小不够严谨（大小相同内容不同的情况
                // 虽然罕见，但校验成本几乎为零，没有理由不做）。
                data.put("apkSha256", apkSha256());
            } catch (IOException ignored) {
                data.put("apkSizeBytes", null);
                data.put("apkSha256", null);
            }
        } else if (!latest.isEmpty()) {
            log.warn("version.json 声明了版本 {}，但 APK 不存在或不可读: {} —— "
                    + "客户端会收到 apkReady=false 从而不提示更新", latest, apkPath);
        }
        return Result.success(data);
    }

    /** APK 的 sha256（十六进制小写），按「mtime + 大小」缓存。 */
    private volatile String cachedSha;
    private volatile long cachedShaMtime = -1L;
    private volatile long cachedShaSize = -1L;

    /**
     * 计算 APK 的 sha256。
     *
     * <p><b>为什么必须缓存</b>：包有 54MB，而版本接口每次启动都会被请求。
     * 不缓存的话每次都要读盘算一遍哈希 —— 在 2C2G 的机器上这是明显的浪费，
     * 并发时更糟。用「mtime + 大小」作为缓存键：文件一换（发新版）就自动失效，
     * 不需要重启，与 version.json 的实时读取策略保持一致。
     */
    private String apkSha256() throws IOException {
        long mtime = Files.getLastModifiedTime(apkPath).toMillis();
        long size = Files.size(apkPath);
        if (cachedSha != null && mtime == cachedShaMtime && size == cachedShaSize) {
            return cachedSha;
        }
        java.security.MessageDigest md;
        try {
            md = java.security.MessageDigest.getInstance("SHA-256");
        } catch (java.security.NoSuchAlgorithmException e) {
            // SHA-256 是 JDK 必备算法，理论上不可达；真出现时降级为不提供校验值
            log.warn("无法初始化 SHA-256，将不提供 apkSha256: {}", e.getMessage());
            return null;
        }
        try (var in = Files.newInputStream(apkPath)) {
            byte[] buf = new byte[8192];
            int n;
            while ((n = in.read(buf)) > 0) {
                md.update(buf, 0, n);
            }
        }
        StringBuilder sb = new StringBuilder(64);
        for (byte b : md.digest()) {
            sb.append(Character.forDigit((b >> 4) & 0xF, 16));
            sb.append(Character.forDigit(b & 0xF, 16));
        }
        String hex = sb.toString();
        cachedSha = hex;
        cachedShaMtime = mtime;
        cachedShaSize = size;
        return hex;
    }

    /**
     * 下载 APK（<b>无需登录</b>）。
     * <p>用 {@link FileSystemResource} 而不是把文件读进内存：
     * 52MB 的包读进 byte[] 会在 2C2G 的服务器上造成明显 GC 压力，
     * 并发下载时内存还会翻倍。
     *
     * <p>未配置时返回 404 而不是 500：客户端把「没有可下载的包」
     * 当成「暂时没有更新」更合理。
     */
    @GetMapping("/download")
    public ResponseEntity<Resource> download() {
        if (apkPath == null || !Files.isReadable(apkPath)) {
            return ResponseEntity.notFound().build();
        }
        long length;
        try {
            length = Files.size(apkPath);
        } catch (IOException e) {
            return ResponseEntity.notFound().build();
        }
        Resource resource = new FileSystemResource(apkPath);
        return ResponseEntity.ok()
                .header(HttpHeaders.CONTENT_DISPOSITION,
                        "attachment; filename=\"campus-run.apk\"")
                .contentType(MediaType.parseMediaType(
                        "application/vnd.android.package-archive"))
                .contentLength(length)
                .body(resource);
    }
}
