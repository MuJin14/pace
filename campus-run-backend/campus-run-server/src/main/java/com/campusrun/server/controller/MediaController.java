package com.campusrun.server.controller;

import com.campusrun.server.service.ThumbnailService;
import org.springframework.http.CacheControl;
import org.springframework.http.MediaType;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.util.concurrent.TimeUnit;

/**
 * 图片缩略图接口。
 *
 * <p>{@code GET /api/v1/media/thumb?path=chat/ab12.jpg&w=400}
 *
 * <h2>为什么要有这个接口</h2>
 *
 * 服务器上行带宽只有约 0.2–0.46 MB/s，而聊天图上限 2MB。
 * 列表里每张都拉原图 → 一张要 5–10 秒，用户感受就是「加载图片巨慢」。
 *
 * <p>不走 {@code /uploads/**} 静态映射而是单独开一个接口，是因为需要
 * **按需处理**：读取原图 → 缩放 → 编码 → 缓存。静态映射只能原样发送。
 *
 * <h2>安全</h2>
 *
 * <ul>
 *   <li>路径穿越由 {@link ThumbnailService} 内的 normalize + startsWith 拦截；</li>
 *   <li>宽度被夹在 32–1600，避免被当成「原图放大器」或 DoS 入口；</li>
 *   <li>只读取 uploadRoot 内已存在的文件，不接受任何写操作。</li>
 * </ul>
 */
@RestController
@RequestMapping("/api/v1/media")
public class MediaController {

    private final ThumbnailService thumbnailService;

    public MediaController(ThumbnailService thumbnailService) {
        this.thumbnailService = thumbnailService;
    }

    /**
     * 取缩略图。
     *
     * <p>失败时返回 **404 而不是 500**：客户端拿到 404 会退回加载原图
     * （见 App 的 `_MediaContent`），这是预期降级路径，不是服务器故障。
     * 返回 500 会让它进错误统计，也会让用户看到「服务器错误」。
     */
    @GetMapping("/thumb")
    public ResponseEntity<byte[]> thumb(
            @RequestParam("path") String path,
            @RequestParam(value = "w", defaultValue = "400") int width) {

        ThumbnailService.Result result = thumbnailService.render(path, width);
        if (!result.isOk()) {
            return ResponseEntity.notFound().build();
        }

        return ResponseEntity.ok()
                .contentType(MediaType.parseMediaType(result.getContentType()))
                // 允许客户端长期缓存：URL 里带了原图的 mtime/size 派生逻辑，
                // 图片变了 URL 不变也不会串（缓存键包含 mtime），
                // 所以这里可以放心给长缓存。
                .cacheControl(CacheControl.maxAge(7, TimeUnit.DAYS).cachePublic())
                .body(result.getData());
    }
}
