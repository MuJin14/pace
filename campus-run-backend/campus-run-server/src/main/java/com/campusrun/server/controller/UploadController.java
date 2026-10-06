package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.service.FileStorageService;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.multipart.MultipartFile;

import java.util.Map;

@RestController
@RequestMapping("/api/v1/upload")
public class UploadController {

    private final FileStorageService fileStorageService;

    public UploadController(FileStorageService fileStorageService) {
        this.fileStorageService = fileStorageService;
    }

    /**
     * 上传头像图片，返回可直接访问的 URL。
     *
     * <p>只返回 URL、不顺带改用户资料：上传与「设为头像」是两个动作，
     * 客户端可以先预览再决定是否保存，失败时也不会把资料改坏。
     */
    @PostMapping("/avatar")
    public Result<Map<String, String>> avatar(@RequestParam("file") MultipartFile file) {
        String url = fileStorageService.saveAvatar(file);
        return Result.success(Map.of("url", url));
    }

    /**
     * 上传聊天图片，返回可直接访问的 URL。
     *
     * <p>与头像走**完全相同的安全校验**（魔术字节识别 / UUID 重命名 / 2MB / 拒绝 SVG），
     * 只是落到 {@code uploads/chat/} 子目录。分成独立接口是为了让存储目录清晰，
     * 也便于将来对聊天图单独做压缩或清理策略。
     */
    @PostMapping("/chat-image")
    public Result<Map<String, String>> chatImage(@RequestParam("file") MultipartFile file) {
        String url = fileStorageService.saveChatImage(file);
        return Result.success(Map.of("url", url));
    }
}
