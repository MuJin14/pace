package com.campusrun.server.update;

import com.fasterxml.jackson.core.type.TypeReference;
import com.fasterxml.jackson.databind.ObjectMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.attribute.FileTime;
import java.util.Map;

/**
 * 版本元数据的内存缓存。
 *
 * <h3>为什么需要缓存</h3>
 *
 * <p>{@code AppVersionHeaderFilter} 要在<b>每一个 API 响应</b>上读版本号。
 * 如果每次都去读磁盘上的 {@code version.json}，就变成
 * 「一次请求 = 一次文件 I/O」。App 打开一个页面会并发十几个请求，
 * 在 2C2G 的服务器上这是纯浪费 —— 而这个文件一次发版才变一次。
 *
 * <h3>为什么不用定时刷新，而是「按 mtime 判断」</h3>
 *
 * <p>定时刷新的问题是「发版到生效」有一段不确定的延迟（取决于周期），
 * 而这段延迟恰恰是最容易出问题的窗口 —— 刚发完版用户却拿不到更新提示，
 * 又要怀疑是不是没生效。
 *
 * <p>按文件修改时间判断则<b>立刻生效</b>：发版脚本写 version.json 会更新 mtime，
 * 下一次请求就命中新内容。代价是每个请求一次 {@code Files.getLastModifiedTime}
 * （stat 调用，不读文件内容），比读整个文件便宜得多。
 *
 * <p>每次请求只做一次 {@code stat}（不读文件内容），在 2C2G 的机器上完全可忽略。
 */
@Component
public class AppVersionStore implements AppVersionProvider {

    private static final Logger log = LoggerFactory.getLogger(AppVersionStore.class);

    private static final String META_FILENAME = "version.json";

    private final Path metaPath;
    private final ObjectMapper objectMapper;

    private volatile AppVersionMetadata cached = AppVersionMetadata.EMPTY;
    private volatile FileTime cachedMtime;
    private volatile long cachedSize = -1L;

    public AppVersionStore(
            @Value("${app-version.apk-path:}") String apkPath,
            ObjectMapper objectMapper) {
        this.objectMapper = objectMapper;
        this.metaPath = resolveMetaPath(apkPath);
    }

    private static Path resolveMetaPath(String apkPath) {
        if (apkPath == null || apkPath.isBlank()) {
            return null;
        }
        Path apk = Paths.get(apkPath).toAbsolutePath().normalize();
        Path parent = apk.getParent();
        return parent == null ? null : parent.resolve(META_FILENAME);
    }

    /**
     * 当前的版本元数据。
     *
     * <p>任何异常都退化成 {@link AppVersionMetadata#EMPTY}（「没有新版本」）：
     * 发版元数据坏掉不该让所有接口出错。
     */
    @Override
    public AppVersionMetadata current() {
        Path path = metaPath;
        if (path == null) {
            return AppVersionMetadata.EMPTY;
        }

        try {
            if (!Files.isReadable(path)) {
                cachedMtime = null;
                cachedSize = -1L;
                cached = AppVersionMetadata.EMPTY;
                return cached;
            }
            FileTime mtime = Files.getLastModifiedTime(path);
            long size = Files.size(path);
            // mtime + size 都相同才认为没变。
            //
            // ⚠️ 曾经额外加了一层「1 秒内不重复 stat」的节流，结果把
            //    「按 mtime 立即生效」这个设计初衷破坏了：发版脚本刚写完
            //    version.json，紧接着的请求仍读到旧值（测试里直接暴露成
            //    两个用例失败）。要的就是**立即生效**，stat 本身足够便宜，
            //    不值得用正确性去换这点开销。
            //
            //    同时看 size 是因为某些文件系统的时间戳精度只有秒级，
            //    同一秒内连续写两次 mtime 可能相同。
            if (mtime.equals(cachedMtime) && size == cachedSize) {
                return cached;
            }
            Map<String, Object> raw = objectMapper.readValue(
                    path.toFile(), new TypeReference<>() {
                    });
            cached = new AppVersionMetadata(
                    str(raw.get("latest")),
                    str(raw.get("minSupported")),
                    str(raw.get("changelog")));
            cachedMtime = mtime;
            cachedSize = size;
            log.info("版本元数据已更新: latest={} minSupported={}",
                    cached.latest(), cached.minSupported().isEmpty()
                            ? "(不强制)" : cached.minSupported());
            return cached;
        } catch (IOException e) {
            log.error("读取 {} 失败，按「没有新版本」处理: {}", path, e.getMessage());
            cached = AppVersionMetadata.EMPTY;
            return cached;
        }
    }

    private static String str(Object v) {
        return v == null ? "" : String.valueOf(v);
    }
}
