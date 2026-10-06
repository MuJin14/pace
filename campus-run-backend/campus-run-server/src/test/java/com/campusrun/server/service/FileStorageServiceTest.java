package com.campusrun.server.service;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import org.junit.jupiter.api.DisplayName;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.mock.web.MockMultipartFile;

import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 头像上传的安全边界。
 *
 * <p>重点不是「能传成功」，而是**挡住伪装文件**：客户端可以把任意内容
 * 改名成 .jpg 并声明 image/jpeg，只校验扩展名/Content-Type 的实现会被绕过。
 * 这里固化「按魔术字节识别 + 服务端命名 + 不能逃出上传目录」。
 */
class FileStorageServiceTest {

    private static final byte[] JPEG = {(byte) 0xFF, (byte) 0xD8, (byte) 0xFF, (byte) 0xE0, 0, 0x10};
    private static final byte[] PNG = {(byte) 0x89, 'P', 'N', 'G', 0x0D, 0x0A, 0x1A, 0x0A, 0, 0};
    private static final byte[] WEBP = {'R', 'I', 'F', 'F', 0, 0, 0, 0, 'W', 'E', 'B', 'P'};

    private FileStorageService service(Path dir) {
        return new FileStorageService(dir.toString(), "http://localhost:8080", null);
    }

    private MockMultipartFile file(String filename, String contentType, byte[] bytes) {
        return new MockMultipartFile("file", filename, contentType, bytes);
    }

    @Test
    @DisplayName("JPEG/PNG/WebP 都能通过，且返回公网可访问 URL")
    void acceptsSupportedFormats(@TempDir Path dir) {
        FileStorageService svc = service(dir);

        String jpg = svc.saveAvatar(file("a.jpg", "image/jpeg", JPEG));
        String png = svc.saveAvatar(file("b.png", "image/png", PNG));
        String webp = svc.saveAvatar(file("c.webp", "image/webp", WEBP));

        assertTrue(jpg.startsWith("http://localhost:8080/uploads/avatar/"), jpg);
        assertTrue(jpg.endsWith(".jpg"));
        assertTrue(png.endsWith(".png"));
        assertTrue(webp.endsWith(".webp"));
    }

    @Test
    @DisplayName("伪装成 .jpg 的非图片内容被拒绝（只信魔术字节，不信扩展名/Content-Type）")
    void rejectsFakeImage(@TempDir Path dir) {
        FileStorageService svc = service(dir);
        // 典型绕过尝试：PHP 脚本改名成 jpg，并声明 image/jpeg
        byte[] php = "<?php system($_GET['c']); ?>".getBytes();

        BusinessException e = assertThrows(BusinessException.class,
                () -> svc.saveAvatar(file("shell.jpg", "image/jpeg", php)));
        assertEquals(ErrorCode.FILE_INVALID.getCode(), e.getCode());
    }

    @Test
    @DisplayName("SVG 被拒绝：可内嵌 <script>，当图片渲染等于 XSS")
    void rejectsSvg(@TempDir Path dir) {
        FileStorageService svc = service(dir);
        byte[] svg = "<svg xmlns=\"http://www.w3.org/2000/svg\"><script>alert(1)</script></svg>"
                .getBytes();

        assertEquals(ErrorCode.FILE_INVALID.getCode(),
                assertThrows(BusinessException.class,
                        () -> svc.saveAvatar(file("x.svg", "image/svg+xml", svg))).getCode());
    }

    @Test
    @DisplayName("超 2MB 被拒绝")
    void rejectsOversize(@TempDir Path dir) {
        FileStorageService svc = service(dir);
        byte[] big = new byte[2 * 1024 * 1024 + 1];
        System.arraycopy(JPEG, 0, big, 0, JPEG.length);

        assertEquals(ErrorCode.FILE_TOO_LARGE.getCode(),
                assertThrows(BusinessException.class,
                        () -> svc.saveAvatar(file("big.jpg", "image/jpeg", big))).getCode());
    }

    @Test
    @DisplayName("空文件被拒绝")
    void rejectsEmpty(@TempDir Path dir) {
        FileStorageService svc = service(dir);

        assertEquals(ErrorCode.FILE_INVALID.getCode(),
                assertThrows(BusinessException.class,
                        () -> svc.saveAvatar(file("e.jpg", "image/jpeg", new byte[0]))).getCode());
    }

    @Test
    @DisplayName("路径穿越的文件名不会逃出上传目录，也不会用原文件名落盘")
    void sanitizesFilename(@TempDir Path dir) throws Exception {
        FileStorageService svc = service(dir);

        String url = svc.saveAvatar(
                file("../../../../evil.jpg", "image/jpeg", JPEG));

        // 落盘名必须是服务端生成的 UUID，不含任何用户提供的片段
        String filename = url.substring(url.lastIndexOf('/') + 1);
        assertTrue(filename.matches("^[0-9a-f]{32}\\.jpg$"), "落盘名应为 UUID: " + filename);
        assertNotEquals("evil.jpg", filename);

        // 确认文件确实在 avatar 子目录里，且上级目录没有被写入
        Path avatarDir = dir.resolve("avatar").toAbsolutePath().normalize();
        assertTrue(Files.exists(avatarDir.resolve(filename)), "文件应落在 avatar 目录内");
        assertTrue(Files.notExists(dir.getParent().resolve("evil.jpg")), "不能写到上传目录之外");
    }

    @Test
    @DisplayName("两个同名上传互不覆盖（服务端重命名）")
    void sameNameDoesNotOverwrite(@TempDir Path dir) {
        FileStorageService svc = service(dir);

        String first = svc.saveAvatar(file("avatar.jpg", "image/jpeg", JPEG));
        String second = svc.saveAvatar(file("avatar.jpg", "image/jpeg", PNG));

        assertNotEquals(first, second, "文件名相同也必须产生不同 URL，否则会互相覆盖");
    }
}
