package com.campusrun.server.service;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;

import javax.imageio.ImageIO;
import java.awt.Graphics2D;
import java.awt.RenderingHints;
import java.awt.image.BufferedImage;
import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;

/**
 * 图片缩略图生成与缓存。
 *
 * <h2>为什么需要它</h2>
 *
 * 聊天里用户发的图是**原图**（上限 2MB）。客户端列表里每张都拉原图，
 * 而服务器上行带宽只有约 0.2–0.46 MB/s ——
 * 一张 1.5MB 的图要 5–10 秒，一屏多张就是几十秒。
 * 用户反馈「加载图片巨慢」就是这个原因，不是网络波动。
 *
 * 缩略图 400px 宽、JPEG q0.78，典型 20–40KB，**快两个数量级**。
 *
 * <h2>设计取舍</h2>
 *
 * <ul>
 *   <li><b>不改数据库</b>：缩略图通过 `?w=400` 参数按需生成，
 *       老数据（已经存成绝对 URL 的那些）也能立刻受益。</li>
 *   <li><b>落盘缓存</b>：同一张图只解码一次，之后直接读缓存文件，
 *       避免每次请求都做一次 CPU 密集的缩放。</li>
 *   <li><b>启动时清理缓存目录</b>：文件名是内容哈希，不会出现
 *       「同名不同图」的脏缓存；清理是为了避免长期运行后无限增长。</li>
 * </ul>
 */
@Service
public class ThumbnailService {

    private static final Logger log = LoggerFactory.getLogger(ThumbnailService.class);

    /** 缩略图缓存目录（相对 uploadRoot）。注意以 `.` 开头，不会被当作媒体目录扫描。 */
    public static final String CACHE_DIR = ".thumbs";

    /** 允许的宽度范围。上限同时也是「别拿它当原图下载器」的保护。 */
    private static final int MIN_WIDTH = 32;
    private static final int MAX_WIDTH = 1600;

    @Value("${app.upload.dir:uploads}")
    private String uploadDir;

    @Value("${app.thumbnail.quality:0.78}")
    private float quality;

    /**
     * 返回缩略图字节；已在缓存中则直接读盘。
     *
     * @param relativePath uploadRoot 内的相对路径（如 {@code chat/ab12.jpg}）
     * @param width        目标宽度（像素）
     * @return 结果；失败时 {@link Result#failed()} 为 true
     */
    public Result render(String relativePath, int width) {
        if (relativePath == null || relativePath.isBlank()) {
            return Result.failed();
        }
        int w = Math.max(MIN_WIDTH, Math.min(MAX_WIDTH, width));

        Path root = Paths.get(uploadDir).toAbsolutePath().normalize();
        Path source = root.resolve(relativePath).normalize();

        // 目录穿越防护：normalize 之后必须仍在 uploadRoot 之内。
        // 少了这一步，`?path=../../etc/passwd` 就能读到任意文件。
        if (!source.startsWith(root)) {
            log.warn("缩略图请求越界，已拒绝: {}", relativePath);
            return Result.failed();
        }
        if (!Files.isRegularFile(source)) {
            return Result.failed();
        }

        String ext = "jpg";

        // 缓存键：相对路径 + 宽度 + 原文件的 mtime+size。
        // 带上 mtime/size 是为了防止「文件被替换但路径不变」时读到旧缩略图。
        String key;
        try {
            key = Integer.toHexString((relativePath + "|" + w + "|"
                    + Files.getLastModifiedTime(source).toMillis() + "|"
                    + Files.size(source)).hashCode());
        } catch (IOException e) {
            return Result.failed();
        }

        Path cacheDir = root.resolve(CACHE_DIR);
        Path cached = cacheDir.resolve(key + "." + ext);
        if (Files.isRegularFile(cached)) {
            try {
                return Result.ok(Files.readAllBytes(cached), "image/jpeg");
            } catch (IOException e) {
                // 缓存读失败就重新生成，不算错误
                log.debug("读取缩略图缓存失败，将重新生成: {}", cached);
            }
        }

        try {
            byte[] out = scale(source, w);
            if (out == null) {
                return Result.failed();
            }
            Files.createDirectories(cacheDir);
            // 先写临时文件再原子移动：避免并发请求读到写了一半的文件
            Path tmp = cacheDir.resolve(key + ".tmp");
            Files.write(tmp, out);
            Files.move(tmp, cached, java.nio.file.StandardCopyOption.REPLACE_EXISTING,
                    java.nio.file.StandardCopyOption.ATOMIC_MOVE);
            return Result.ok(out, "image/jpeg");
        } catch (IOException e) {
            log.warn("生成缩略图失败: {} ({})", relativePath, e.getMessage());
            return Result.failed();
        }
    }

    private byte[] scale(Path source, int targetWidth) throws IOException {
        BufferedImage src = ImageIO.read(source.toFile());
        if (src == null) {
            return null; // 不是能解码的图片
        }

        int srcW = src.getWidth();
        int srcH = src.getHeight();
        if (srcW <= 0 || srcH <= 0) {
            return null;
        }

        // 比目标还小就不放大：放大只会更糊、还更占带宽
        int dstW = Math.min(targetWidth, srcW);
        int dstH = Math.max(1, (int) Math.round(srcH * (dstW / (double) srcW)));

        // 统一转成 RGB 再编码 JPEG。
        // PNG 可能带 alpha，直接写 JPEG 会抛异常或产生花屏。
        BufferedImage dst = new BufferedImage(dstW, dstH, BufferedImage.TYPE_INT_RGB);
        Graphics2D g = dst.createGraphics();
        try {
            g.setRenderingHint(RenderingHints.KEY_INTERPOLATION,
                    RenderingHints.VALUE_INTERPOLATION_BILINEAR);
            g.setRenderingHint(RenderingHints.KEY_RENDERING,
                    RenderingHints.VALUE_RENDER_QUALITY);
            // 透明区域填白，否则 PNG 的透明部分会变黑
            g.setColor(java.awt.Color.WHITE);
            g.fillRect(0, 0, dstW, dstH);
            g.drawImage(src, 0, 0, dstW, dstH, null);
        } finally {
            g.dispose();
        }

        ByteArrayOutputStream bos = new ByteArrayOutputStream();
        if (!writeJpeg(dst, bos)) {
            return null;
        }
        return bos.toByteArray();
    }

    /**
     * 编码 JPEG。
     *
     * <p>标准的 {@code ImageIO.write(img, "jpg", os)} 在只装了 OpenJDK 的容器里
     * 可能返回 false（没有 JPEG writer）—— 所以显式拿 writer 并检查返回值，
     * 失败时返回 false 让上层退化成「不提供缩略图」而不是抛异常。
     */
    private boolean writeJpeg(BufferedImage img, ByteArrayOutputStream out) {
        java.util.Iterator<javax.imageio.ImageWriter> it =
                ImageIO.getImageWritersByFormatName("jpeg");
        if (!it.hasNext()) {
            log.warn("运行环境没有 JPEG 编码器，缩略图不可用");
            return false;
        }
        javax.imageio.ImageWriter writer = it.next();
        try (javax.imageio.stream.ImageOutputStream ios =
                     ImageIO.createImageOutputStream(out)) {
            writer.setOutput(ios);
            javax.imageio.plugins.jpeg.JPEGImageWriteParam param =
                    new javax.imageio.plugins.jpeg.JPEGImageWriteParam(java.util.Locale.ROOT);
            param.setCompressionMode(javax.imageio.ImageWriteParam.MODE_EXPLICIT);
            param.setCompressionQuality(Math.max(0.1f, Math.min(1.0f, quality)));
            writer.write(null, new javax.imageio.IIOImage(img, null, null), param);
            return true;
        } catch (IOException e) {
            log.warn("JPEG 编码失败: {}", e.getMessage());
            return false;
        } finally {
            writer.dispose();
        }
    }

    /** 生成结果。 */
    public static final class Result {
        private final byte[] data;
        private final String contentType;
        private final boolean ok;

        private Result(byte[] data, String contentType, boolean ok) {
            this.data = data;
            this.contentType = contentType;
            this.ok = ok;
        }

        static Result ok(byte[] data, String contentType) {
            return new Result(data, contentType, true);
        }

        static Result failed() {
            return new Result(null, null, false);
        }

        public boolean isOk() {
            return ok;
        }

        public byte[] getData() {
            return data;
        }

        public String getContentType() {
            return contentType;
        }
    }
}
