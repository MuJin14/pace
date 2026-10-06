package com.campusrun.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import java.io.IOException;
import java.nio.file.FileStore;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 上传前的磁盘余量守卫。
 *
 * <p><b>为什么需要它</b>：上传接口是**唯一**能让外部往服务器写数据的地方。
 * 真的把磁盘写满会连带 MySQL 一起挂掉 —— 那不是「图片功能坏了」，
 * 而是整个 App 下线（登录、跑步记录、聊天全部报错）。
 *
 * <p>用 {@link FileStore#getUsableSpace()} 而不是「累加目录大小」：
 * <ul>
 *   <li>它是 O(1) 的系统调用，不需要遍历目录；</li>
 *   <li>它反映的是**真实**剩余空间 —— 目录里还有 Docker 镜像、日志、
 *       MySQL 数据文件，只统计 uploads 会严重高估可用空间。</li>
 * </ul>
 *
 * <p>阈值是**保留余量**而不是总量上限：磁盘本来就要留 20% 给系统
 * （MySQL 写入、日志轮转、Docker 层缓存都需要空间）。
 * 低于余量时只拒绝**上传**，不影响已有数据和其它接口。
 */
@Service
public class StorageGuard {

    private static final Logger log = LoggerFactory.getLogger(StorageGuard.class);

    /** 低于这个剩余空间就拒绝新上传。 */
    private final long minFreeBytes;

    private final Path uploadRoot;

    public StorageGuard(
            @Value("${app.upload-dir:uploads}") String uploadDir,
            @Value("${app.storage.min-free-mb:512}") long minFreeMb) {
        this.uploadRoot = Paths.get(uploadDir).toAbsolutePath().normalize();
        this.minFreeBytes = Math.max(0, minFreeMb) * 1024 * 1024;
    }

    /** 供测试与日志使用。 */
    public long minFreeBytes() {
        return minFreeBytes;
    }

    /**
     * 是否还有足够空间接受一次上传。
     *
     * <p>取不到文件系统信息时**放行**（返回 true）：
     * 宁可让一次上传成功，也不要因为探测失败把整条链路打死。
     */
    public boolean hasRoom() {
        Long free = usableBytes();
        if (free == null) {
            return true;
        }
        if (free < minFreeBytes) {
            log.error("磁盘剩余空间不足，拒绝上传: 剩余 {} MB < 要求 {} MB",
                    free / 1024 / 1024, minFreeBytes / 1024 / 1024);
            return false;
        }
        return true;
    }

    /** 剩余可用字节；探测失败返回 null。 */
    public Long usableBytes() {
        try {
            Path probe = Files.exists(uploadRoot) ? uploadRoot : uploadRoot.getParent();
            if (probe == null || !Files.exists(probe)) {
                return null;
            }
            FileStore store = Files.getFileStore(probe);
            return store.getUsableSpace();
        } catch (IOException e) {
            log.warn("无法探测磁盘剩余空间: {}", e.getMessage());
            return null;
        }
    }
}
