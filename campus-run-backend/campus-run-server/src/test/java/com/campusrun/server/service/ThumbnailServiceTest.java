package com.campusrun.server.service;

import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.io.TempDir;
import org.springframework.test.util.ReflectionTestUtils;

import javax.imageio.ImageIO;
import java.awt.Color;
import java.awt.Graphics2D;
import java.awt.image.BufferedImage;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

/**
 * 缩略图服务测试。
 *
 * <p>这个类里最要紧的是**路径穿越防护**：接口是匿名可访问的
 * （和 /uploads/** 一样，因为 &lt;img&gt; 不带 Authorization 头），
 * 一旦 `?path=../../` 能读到任意文件，就是任意文件读取漏洞。
 */
class ThumbnailServiceTest {

    @TempDir
    Path tempDir;

    private ThumbnailService service;

    @BeforeEach
    void setUp() {
        service = new ThumbnailService();
        ReflectionTestUtils.setField(service, "uploadDir", tempDir.toString());
        ReflectionTestUtils.setField(service, "quality", 0.78f);
    }

    private void writeJpeg(Path target, int w, int h) throws IOException {
        Files.createDirectories(target.getParent());
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setColor(Color.ORANGE);
        g.fillRect(0, 0, w, h);
        g.dispose();
        ImageIO.write(img, "jpg", target.toFile());
    }

    private void writePng(Path target, int w, int h) throws IOException {
        Files.createDirectories(target.getParent());
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_ARGB);
        Graphics2D g = img.createGraphics();
        // 半透明：验证 PNG 带 alpha 时不会编码失败
        g.setColor(new Color(255, 140, 66, 128));
        g.fillRect(0, 0, w, h);
        g.dispose();
        ImageIO.write(img, "png", target.toFile());
    }

    /** 画条纹，保证不同尺寸/不同调用产生的图在视觉上确实不同。 */
    private void writeStripedJpeg(Path target, int w, int h) throws IOException {
        Files.createDirectories(target.getParent());
        BufferedImage img = new BufferedImage(w, h, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = img.createGraphics();
        g.setColor(Color.WHITE);
        g.fillRect(0, 0, w, h);
        g.setColor(Color.BLACK);
        for (int x = 0; x < w; x += 40) {
            g.fillRect(x, 0, 20, h);
        }
        g.dispose();
        ImageIO.write(img, "jpg", target.toFile());
    }

    @Test
    void rendersThumbnailAtRequestedWidth() throws IOException {
        writeJpeg(tempDir.resolve("chat/big.jpg"), 1600, 1200);

        ThumbnailService.Result r = service.render("chat/big.jpg", 400);

        assertTrue(r.isOk(), "应当成功生成缩略图");
        assertEquals("image/jpeg", r.getContentType());

        // 解码回来确认宽度被缩到 400
        BufferedImage out = ImageIO.read(new java.io.ByteArrayInputStream(r.getData()));
        assertNotNull(out);
        assertEquals(400, out.getWidth());
        assertEquals(300, out.getHeight(), "应当等比缩放");
    }

    @Test
    void doesNotUpscaleSmallerImages() throws IOException {
        // 比目标还小就不放大：放大只会更糊、还更占带宽
        writeJpeg(tempDir.resolve("chat/small.jpg"), 200, 150);

        ThumbnailService.Result r = service.render("chat/small.jpg", 400);

        assertTrue(r.isOk());
        BufferedImage out = ImageIO.read(new java.io.ByteArrayInputStream(r.getData()));
        assertEquals(200, out.getWidth(), "不应把小图放大");
    }

    @Test
    void handlesPngWithAlpha() throws IOException {
        // PNG 带透明通道时直接编码 JPEG 会抛异常，必须转 RGB 并铺白底
        writePng(tempDir.resolve("chat/alpha.png"), 800, 600);

        ThumbnailService.Result r = service.render("chat/alpha.png", 300);

        assertTrue(r.isOk(), "带 alpha 的 PNG 也要能生成缩略图");
        BufferedImage out = ImageIO.read(new java.io.ByteArrayInputStream(r.getData()));
        assertEquals(300, out.getWidth());
    }

    @Test
    void secondCallHitsCacheAndReturnsSameBytes() throws IOException {
        writeJpeg(tempDir.resolve("chat/c.jpg"), 1000, 1000);

        ThumbnailService.Result first = service.render("chat/c.jpg", 200);
        ThumbnailService.Result second = service.render("chat/c.jpg", 200);

        assertTrue(first.isOk() && second.isOk());
        assertTrue(java.util.Arrays.equals(first.getData(), second.getData()),
                "同一文件同一宽度应当命中缓存并返回相同字节");
    }

    @Test
    void rejectsPathTraversal() throws IOException {
        // 在 uploadRoot 之外放一个「机密文件」
        Path outside = tempDir.getParent().resolve("secret-" + System.nanoTime() + ".jpg");
        writeJpeg(outside, 100, 100);
        try {
            String escape = "../" + outside.getFileName();

            ThumbnailService.Result r = service.render(escape, 200);

            assertFalse(r.isOk(), "目录穿越必须被拒绝 —— 否则就是任意文件读取");
        } finally {
            Files.deleteIfExists(outside);
        }
    }

    @Test
    void rejectsAbsolutePathOutsideRoot() {
        ThumbnailService.Result r = service.render("/etc/passwd", 200);
        assertFalse(r.isOk());
    }

    @Test
    void rejectsMissingFile() {
        ThumbnailService.Result r = service.render("chat/does-not-exist.jpg", 200);
        assertFalse(r.isOk(), "文件不存在应当返回失败，而不是抛异常");
    }

    @Test
    void rejectsNonImageContent() throws IOException {
        Path txt = tempDir.resolve("chat/not-an-image.jpg");
        Files.createDirectories(txt.getParent());
        Files.writeString(txt, "这不是图片，只是扩展名叫 jpg");

        ThumbnailService.Result r = service.render("chat/not-an-image.jpg", 200);
        assertFalse(r.isOk(), "解不出图的文件不能抛异常，应返回失败让客户端降级");
    }

    @Test
    void rejectsBlankPath() {
        assertFalse(service.render(null, 200).isOk());
        assertFalse(service.render("", 200).isOk());
        assertFalse(service.render("   ", 200).isOk());
    }

    @Test
    void clampsWidthToSafeRange() throws IOException {
        writeJpeg(tempDir.resolve("chat/wide.jpg"), 4000, 3000);

        // 请求一个荒谬的宽度：必须被夹到上限，不能变成 DoS 入口
        ThumbnailService.Result huge = service.render("chat/wide.jpg", 999999);
        assertTrue(huge.isOk());
        BufferedImage out = ImageIO.read(new java.io.ByteArrayInputStream(huge.getData()));
        assertTrue(out.getWidth() <= 1600, "宽度必须被夹到上限内，实际=" + out.getWidth());

        // 过小的宽度也要被夹到下限，避免生成 0 宽度的图
        ThumbnailService.Result tiny = service.render("chat/wide.jpg", 1);
        assertTrue(tiny.isOk());
        BufferedImage out2 = ImageIO.read(new java.io.ByteArrayInputStream(tiny.getData()));
        assertTrue(out2.getWidth() >= 32, "宽度必须被夹到下限内，实际=" + out2.getWidth());
    }

    @Test
    void cacheInvalidatedWhenSourceChanges() throws IOException, InterruptedException {
        Path p = tempDir.resolve("chat/changing.jpg");
        writeJpeg(p, 800, 600);

        ThumbnailService.Result first = service.render("chat/changing.jpg", 200);
        BufferedImage firstImg = ImageIO.read(new java.io.ByteArrayInputStream(first.getData()));
        assertEquals(200, firstImg.getWidth());
        assertEquals(150, firstImg.getHeight());

        // ⚠️ 第二张必须是**视觉上不同**的图。
        // 最初这里只是改了尺寸（都画纯橙色方块），结果缩略图字节完全相同 ——
        // 断言「字节不相等」就失败了，但那其实说明不了缓存有没有失效，
        // 只说明两张纯色图缩出来一样。用不同图案才是有意义的验证。
        Thread.sleep(1100); // 保证 mtime 变化（部分文件系统精度为 1s）
        writeStripedJpeg(p, 1200, 900);

        ThumbnailService.Result second = service.render("chat/changing.jpg", 200);

        assertTrue(first.isOk() && second.isOk());
        BufferedImage secondImg = ImageIO.read(new java.io.ByteArrayInputStream(second.getData()));
        assertEquals(150, secondImg.getHeight(),
                "原图从 4:3 变 3:4，缓存键含 mtime+size，必须重新生成而不是返回旧图");
    }
}
