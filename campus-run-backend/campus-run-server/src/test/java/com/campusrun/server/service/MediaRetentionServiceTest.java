package com.campusrun.server.service;

import com.campusrun.server.mapper.MessageMapper;
import org.junit.jupiter.api.Test;
import org.mockito.Mockito;
import org.junit.jupiter.api.io.TempDir;

import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.attribute.FileTime;
import java.time.Instant;
import java.time.temporal.ChronoUnit;
import java.util.ArrayList;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 聊天图片保留策略。
 *
 * <p>重点不是「能不能删」，而是**不能删错**：
 * 仍在被引用的文件、以及还没过期的文件，一个都不能碰。
 */
class MediaRetentionServiceTest {

    /**
     * 用 Mockito 而不是手写 fake：MessageMapper 继承 MyBatis-Plus 的 BaseMapper，
     * 有几十个抽象方法，手写一个 fake 要全部实现 —— 噪音大于价值。
     */
    private MessageMapper mapper(List<String> referenced, int[] cleared) {
        MessageMapper m = Mockito.mock(MessageMapper.class);
        Mockito.when(m.selectReferencedMediaUrls()).thenReturn(referenced);
        Mockito.when(m.clearExpiredMediaUrls(Mockito.anyInt())).thenAnswer(inv -> {
            cleared[0]++;
            return 0;
        });
        return m;
    }

    private Path chatDir(Path root) throws IOException {
        Path d = root.resolve("chat");
        Files.createDirectories(d);
        return d;
    }

    private Path writeFile(Path dir, String name, int daysOld) throws IOException {
        Path p = dir.resolve(name);
        Files.writeString(p, "x");
        Files.setLastModifiedTime(p,
                FileTime.from(Instant.now().minus(daysOld, ChronoUnit.DAYS)));
        return p;
    }

    @Test
    void deletesUnreferencedExpiredFiles(@TempDir Path root) throws IOException {
        Path chat = chatDir(root);
        writeFile(chat, "expired.png", 200);
        writeFile(chat, "fresh.png", 1);

        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of(), new int[1]));

        assertEquals(1, svc.cleanupExpired(), "只应删掉过期的那一个");
        assertTrue(Files.exists(chat.resolve("fresh.png")), "未过期的文件必须保留");
    }

    @Test
    void keepsReferencedFilesEvenWhenExpired(@TempDir Path root) throws IOException {
        Path chat = chatDir(root);
        writeFile(chat, "still-used.png", 500);

        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of("https://api.hibiscus.wiki:8443/uploads/chat/still-used.png"),
                        new int[1]));

        assertEquals(0, svc.cleanupExpired(),
                "仍被消息引用的文件不能删 —— 删了用户会看到「图片加载失败」");
        assertTrue(Files.exists(chat.resolve("still-used.png")));
    }

    @Test
    void matchesReferencedUrlByFilenameNotFullUrl(@TempDir Path root) throws IOException {
        Path chat = chatDir(root);
        writeFile(chat, "abc.png", 500);

        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of("http://122.51.191.145:8080/uploads/chat/abc.png"),
                        new int[1]));

        assertEquals(0, svc.cleanupExpired(),
                "应按文件名比对，兼容历史域名变化");
    }

    @Test
    void clearsExpiredUrlsBeforeDeletingFiles(@TempDir Path root) throws IOException {
        chatDir(root);
        int[] cleared = new int[1];
        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of(), cleared));

        svc.cleanupExpired();

        assertEquals(1, cleared[0], "应当先把过期消息的 media_url 置空");
    }

    @Test
    void zeroOrNegativeRetentionDisablesCleanup(@TempDir Path root) throws IOException {
        Path chat = chatDir(root);
        writeFile(chat, "ancient.png", 9999);
        int[] cleared = new int[1];
        MediaRetentionService svc = new MediaRetentionService(root.toString(), 0,
                mapper(List.of(), cleared));

        assertEquals(0, svc.cleanupExpired(), "保留天数为 0 表示不清理");
        assertEquals(0, cleared[0]);
        assertTrue(Files.exists(chat.resolve("ancient.png")));
    }

    @Test
    void missingChatDirIsNotAnError(@TempDir Path root) {
        // 还没人传过图 → 目录不存在。不该抛异常（定时任务抛异常会中断后续调度）
        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of(), new int[1]));
        assertEquals(0, svc.cleanupExpired());
    }

    @Test
    void doesNotDeleteFilesFromOtherDirs(@TempDir Path root) throws IOException {
        // 头像目录不该被聊天图片的保留策略碰到
        Path avatarDir = root.resolve("avatar");
        Files.createDirectories(avatarDir);
        writeFile(avatarDir, "old-avatar.png", 999);

        Path chat = chatDir(root);
        writeFile(chat, "old-chat.png", 999);

        MediaRetentionService svc = new MediaRetentionService(root.toString(), 90,
                mapper(List.of(), new int[1]));

        assertEquals(1, svc.cleanupExpired());
        assertTrue(Files.exists(avatarDir.resolve("old-avatar.png")),
                "头像不归聊天图片保留策略管 —— 用户头像过期会很奇怪");
    }
}
