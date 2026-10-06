package com.campusrun.server.service;

import com.campusrun.server.mapper.MessageMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.scheduling.annotation.Scheduled;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.List;
import java.util.stream.Stream;

/**
 * 聊天图片的保留策略：过期后删文件，**但保留消息**。
 *
 * <p><b>为什么需要</b>：上传接口是外部唯一能往服务器写数据的地方，
 * 不管的话磁盘会被慢慢填满。填满的后果不是「图片打不开」，
 * 而是 MySQL 一起挂掉 —— 整个 App 下线。
 *
 * <p><b>为什么默认 90 天而不是 7 天</b>：
 * 7 天会让用户翻一周前的聊天时图片全变占位符，观感上像 App 坏了。
 * 而体积上完全没必要那么激进（实测整个 uploads 目录才 1.2MB）。
 * 留下更长的历史，代价是几乎为零。
 *
 * <p><b>为什么「删文件不删消息」</b>：
 * 直接删消息会让聊天记录凭空少几条，用户会以为丢数据了。
 * 现在只删文件、把 `message.media_url` 置空，前端据此显示
 * 「图片已过期」—— 对话的**结构**保持完整，只是内容到期了。
 *
 * <p><b>只清理不再被任何消息引用的文件</b>：
 * 这是关键的安全约束。如果只按文件时间删，会删掉「旧消息里的新图片」
 * （比如用户今天重新上传了头像、但文件是按创建时间算的旧文件），
 * 以及仍在被引用的图片。先查出全部仍在引用的 URL，再删不在其中的文件。
 */
@Service
public class MediaRetentionService {

    private static final Logger log = LoggerFactory.getLogger(MediaRetentionService.class);

    /** 聊天图片目录（相对 uploadDir）。头像不在此列。 */
    private static final String DIR_CHAT = "chat";

    private final Path uploadRoot;
    private final MessageMapper messageMapper;
    private final int retentionDays;

    public MediaRetentionService(
            @Value("${app.upload-dir:uploads}") String uploadDir,
            @Value("${app.media.retention-days:90}") int retentionDays,
            MessageMapper messageMapper) {
        this.uploadRoot = Paths.get(uploadDir).toAbsolutePath().normalize();
        this.retentionDays = retentionDays;
        this.messageMapper = messageMapper;
        log.info("聊天图片保留策略: {} 天（0 或负数 = 不清理）", retentionDays);
    }

    /**
     * 每天凌晨 4:10 清理过一次的聊天图片。
     *
     * <p>选 4:10 而不是 3:00：排行榜/目标的定时任务在凌晨跑，
     * 错开可以避免同时抢数据库连接。
     */
    @Scheduled(cron = "0 10 4 * * ?")
    public void scheduledCleanup() {
        try {
            int removed = cleanupExpired();
            if (removed > 0) {
                log.info("聊天图片保留策略: 清理了 {} 个过期文件", removed);
            }
        } catch (Exception e) {
            // 定时任务抛异常会中断后续调度，这里必须吞掉
            log.error("聊天图片清理失败", e);
        }
    }

    /**
     * 执行一次清理，返回删除的文件数。
     *
     * <p>先处理数据库（把过期消息的 media_url 置空），再删磁盘文件。
     * 顺序很关键：反过来的话，如果删文件成功但改库失败，
     * 消息会指向一个不存在的文件（表现为「图片加载失败」），
     * 而现在是「先标记过期、再删文件」，中途失败最坏也只是文件多留一天。
     */
    public int cleanupExpired() {
        if (retentionDays <= 0) {
            return 0;
        }
        Path chatDir = uploadRoot.resolve(DIR_CHAT).normalize();
        if (!Files.isDirectory(chatDir)) {
            return 0;
        }

        Instant cutoff = Instant.now().minus(retentionDays, ChronoUnit.DAYS);

        // ① 先清掉过期消息的 media_url，让前端能显示「图片已过期」
        int cleared = clearExpiredUrls();
        if (cleared > 0) {
            log.info("已将 {} 条过期图片消息标记为「图片已过期」", cleared);
        }

        // ② 再删磁盘上「没人引用 + 已过期」的文件
        List<String> referenced = messageMapper.selectReferencedMediaUrls();
        int deleted = 0;
        try (Stream<Path> files = Files.list(chatDir)) {
            List<Path> candidates = files.filter(Files::isRegularFile).toList();
            for (Path p : candidates) {
                if (isReferenced(referenced, p)) {
                    continue;
                }
                try {
                    if (!isOlderThan(p, cutoff)) {
                        continue;
                    }
                    if (Files.deleteIfExists(p)) {
                        deleted++;
                    }
                } catch (IOException e) {
                    // 单个文件删不掉不该中断整批（可能是权限或正被读取）
                    log.warn("删除过期图片失败 {}: {}", p.getFileName(), e.getMessage());
                }
            }
        } catch (IOException e) {
            log.warn("扫描聊天图片目录失败: {}", e.getMessage());
        }
        return deleted;
    }

    /** 把超过保留期的图片消息的 media_url 置空。 */
    private int clearExpiredUrls() {
        try {
            return messageMapper.clearExpiredMediaUrls(retentionDays);
        } catch (Exception e) {
            log.warn("清空过期 media_url 失败（跳过，不影响删文件）: {}", e.getMessage());
            return 0;
        }
    }

    /** URL 是否仍被某条消息引用。按文件名比对，兼容域名/端口变化。 */
    private boolean isReferenced(List<String> referencedUrls, Path file) {
        String name = file.getFileName().toString();
        for (String url : referencedUrls) {
            if (url != null && url.endsWith(name)) {
                return true;
            }
        }
        return false;
    }

    private boolean isOlderThan(Path p, Instant cutoff) throws IOException {
        return Files.getLastModifiedTime(p).toInstant().isBefore(cutoff);
    }
}
