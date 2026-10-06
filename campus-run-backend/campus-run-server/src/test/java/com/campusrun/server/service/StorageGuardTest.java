package com.campusrun.server.service;

import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;

import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 上传前的磁盘余量守卫。
 *
 * <p>上传是外部**唯一**能往服务器写数据的入口。写满磁盘的后果不是
 * 「图片打不开」，而是 MySQL 一起挂掉 —— 整个 App 下线。
 * 所以这条防线值得单测。
 */
class StorageGuardTest {

    @TempDir
    Path tmp;

    @Test
    void allowsUploadWhenPlentyOfRoom() {
        // 真实磁盘上不可能只剩不到 1MB，所以阈值设成 0 时一定放行
        StorageGuard guard = new StorageGuard(tmp.toString(), 0);
        assertTrue(guard.hasRoom(), "阈值 0 时必须放行");
        Long free = guard.usableBytes();
        assertNotNull(free, "应当能探到文件系统");
        assertTrue(free > 0, "剩余空间应为正数");
    }

    @Test
    void refusesWhenRequiredFreeExceedsDiskCapacity() {
        // 用一个不可能的阈值（比整块磁盘还大）来触发拒绝分支，
        // 而不需要真的把磁盘写满。
        Long free = new StorageGuard(tmp.toString(), 0).usableBytes();
        assertNotNull(free);
        long impossibleMb = (free / 1024 / 1024) + 1024 * 1024; // 远超实际容量

        StorageGuard guard = new StorageGuard(tmp.toString(), impossibleMb);
        assertFalse(guard.hasRoom(), "剩余空间低于要求时必须拒绝上传");
        assertTrue(guard.minFreeBytes() > free);
    }

    @Test
    void treatsNonexistentUploadDirGracefully() {
        // 目录还不存在（首次部署）时不该崩，也不该误判为「没空间」
        StorageGuard guard = new StorageGuard(tmp.resolve("not-created-yet").toString(), 0);
        assertTrue(guard.hasRoom(), "目录不存在时不应拒绝 —— 首次上传会自己创建它");
        assertNotNull(guard.usableBytes(), "应当探测父目录所在文件系统");
    }

    @Test
    void negativeThresholdIsClampedToZero() {
        // 负值（配置写错）不该变成「永远拒绝」
        StorageGuard guard = new StorageGuard(tmp.toString(), -100);
        assertTrue(guard.minFreeBytes() == 0, "负数阈值应被夹到 0");
        assertTrue(guard.hasRoom());
    }
}
