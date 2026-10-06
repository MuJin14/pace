package com.campusrun.server.service;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Service;
import org.springframework.web.multipart.MultipartFile;

import java.io.IOException;
import java.io.InputStream;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.nio.file.StandardCopyOption;
import java.util.UUID;

/**
 * 图片上传（头像 / 聊天图片 / 表情包资源）。
 *
 * <p>安全要点（都是容易被忽略、被利用的）：
 * <ol>
 *   <li><b>不信任文件名与 Content-Type</b>：客户端可以随便伪造。这里读取文件头魔术字节
 *       判断真实类型，扩展名由服务端按识别结果决定。</li>
 *   <li><b>不把用户的文件名落盘</b>：用 UUID 重命名，避免 {@code ../../etc/passwd} 这类
 *       路径穿越和「同名覆盖」。</li>
 *   <li><b>独立目录</b>：只往配置的上传根目录下写，且落盘路径由服务端拼装，
 *       不接受任何来自请求的路径片段。</li>
 *   <li><b>限制大小</b>：由 Spring multipart 配置（2MB）+ 这里再校验一次兜底。</li>
 *   <li><b>拒绝 SVG</b>：SVG 可内嵌 {@code <script>}，当图片渲染等于 XSS。</li>
 * </ol>
 *
 * <p>三类图片共用同一套校验，只有落地子目录不同 —— 统一走 {@link #saveImage}，
 * 避免「头像校验严、聊天图漏检」这种只在某个入口才出现的漏洞。
 */
@Service
public class FileStorageService {

    private static final Logger log = LoggerFactory.getLogger(FileStorageService.class);

    private static final long MAX_BYTES = 2 * 1024 * 1024L;

    /** 头像子目录。 */
    public static final String DIR_AVATAR = "avatar";
    /** 聊天图片子目录。 */
    public static final String DIR_CHAT = "chat";

    private final Path uploadRoot;
    private final String publicBaseUrl;

    /** 磁盘余量守卫：上传是外部唯一能写数据的入口，必须挡住写满磁盘的情况。 */
    private final StorageGuard storageGuard;

    public FileStorageService(
            @Value("${app.upload-dir:uploads}") String uploadDir,
            @Value("${app.public-base-url:http://localhost:8080}") String publicBaseUrl,
            StorageGuard storageGuard) {
        // 只允许写到配置目录下：resolve 后不再接受外部路径片段
        this.uploadRoot = Paths.get(uploadDir).toAbsolutePath().normalize();
        this.publicBaseUrl = publicBaseUrl.endsWith("/")
                ? publicBaseUrl.substring(0, publicBaseUrl.length() - 1)
                : publicBaseUrl;
        this.storageGuard = storageGuard;
    }


    /**
     * 启动自检：确认上传目录存在且**可写**。
     *
     * <p>为什么必须做这一步（真实事故：线上「上传头像失败 code=6003」）：
     * 上传目录出错（不存在 / 属主不对 / 只读）时，问题<b>只在用户第一次上传时</b>
     * 才暴露，报的还只是一句「图片保存失败，请重试」—— 排查要从日志翻到 IOException 堆栈。
     * 启动时探测一次，就能把「部署配置错了」和「用户传了坏图」区分开。
     *
     * <p>只**告警不阻断启动**：上传功能坏了不该让整个 App 起不来
     * （聊天、跑步、排行榜都不依赖它）。日志里给出可操作的修复命令。
     */
    @jakarta.annotation.PostConstruct
    void verifyUploadRootWritable() {
        try {
            Files.createDirectories(uploadRoot);
        } catch (IOException e) {
            log.error("上传目录创建失败: {} —— 上传功能将不可用。"
                            + "若在容器里，检查挂载卷属主是否为运行用户（app）："
                            + "docker exec -u root <容器> chown -R app:app {}",
                    uploadRoot, uploadRoot, e);
            return;
        }
        if (!Files.isWritable(uploadRoot)) {
            log.error("上传目录不可写: {} —— 上传功能将不可用。"
                            + "常见原因：命名卷以 root 创建、容器以非 root 运行。"
                            + "修复：docker exec -u root <容器> chown -R app:app {}",
                    uploadRoot, uploadRoot);
            return;
        }
        log.info("上传目录就绪: {} (可写, publicBaseUrl={})", uploadRoot, publicBaseUrl);
    }

    /**
     * 保存头像图片。
     *
     * @param file 上传文件
     * @return 可直接访问的公开 URL
     * @throws BusinessException 文件为空 / 超限 / 类型不受支持
     */
    public String saveAvatar(MultipartFile file) {
        return saveImage(file, DIR_AVATAR);
    }

    /**
     * 保存聊天图片。
     *
     * <p>与头像走完全相同的安全校验，只有子目录不同。
     *
     * @param file 上传文件
     * @return 可直接访问的公开 URL
     * @throws BusinessException 文件为空 / 超限 / 类型不受支持
     */
    public String saveChatImage(MultipartFile file) {
        return saveImage(file, DIR_CHAT);
    }

    /**
     * 校验并保存一张图片到指定子目录。
     *
     * @param file   上传文件
     * @param subDir 子目录名（只应是本类常量，不接受请求传入的任意值）
     * @return 公开 URL
     */
    private String saveImage(MultipartFile file, String subDir) {
        if (file == null || file.isEmpty()) {
            throw new BusinessException(ErrorCode.FILE_INVALID.getCode(), "请选择要上传的图片");
        }
        if (file.getSize() > MAX_BYTES) {
            throw new BusinessException(ErrorCode.FILE_TOO_LARGE.getCode(), "图片不能超过 2MB");
        }

        byte[] header = readHeader(file);
        String ext = detectImageExtension(header);
        if (ext == null) {
            throw new BusinessException(ErrorCode.FILE_INVALID.getCode(),
                    "只支持 JPG / PNG / WebP 格式的图片");
        }

        // 磁盘余量守卫：写满磁盘会让 MySQL 一起挂掉 ——
        // 那不是「图片功能坏了」，而是整个 App 下线。
        // 放在生成文件名之前：拒绝时不该留下任何痕迹。
        if (storageGuard != null && !storageGuard.hasRoom()) {
            throw new BusinessException(ErrorCode.FILE_SAVE_ERROR.getCode(),
                    "服务器存储空间不足，暂时无法上传，请稍后再试");
        }

        // 服务端生成文件名：不采用用户提供的任何文件名字段
        String filename = UUID.randomUUID().toString().replace("-", "") + "." + ext;
        Path dir = uploadRoot.resolve(subDir).normalize();
        try {
            Files.createDirectories(dir);
            Path target = dir.resolve(filename).normalize();
            // 双保险：即使 filename 被污染，也不能逃出 dir
            if (!target.startsWith(dir)) {
                throw new BusinessException(ErrorCode.FILE_INVALID.getCode(), "非法的文件路径");
            }
            try (InputStream in = file.getInputStream()) {
                Files.copy(in, target, StandardCopyOption.REPLACE_EXISTING);
            }
            log.info("图片已保存: {}/{}", subDir, filename);
            return publicBaseUrl + "/uploads/" + subDir + "/" + filename;
        } catch (IOException e) {
            log.error("图片保存失败", e);
            throw new BusinessException(ErrorCode.FILE_SAVE_ERROR.getCode(), "图片保存失败，请重试");
        }
    }

    private byte[] readHeader(MultipartFile file) {
        byte[] buf = new byte[12];
        try (InputStream in = file.getInputStream()) {
            int read = in.read(buf);
            if (read <= 0) {
                throw new BusinessException(ErrorCode.FILE_INVALID.getCode(), "图片内容为空");
            }
        } catch (IOException e) {
            throw new BusinessException(ErrorCode.FILE_INVALID.getCode(), "图片读取失败");
        }
        return buf;
    }

    /**
     * 按魔术字节识别图片类型。
     *
     * <p>为什么不用 {@code file.getContentType()}：它是客户端自己报的，把 .php 改名为 .jpg
     * 再声明 image/jpeg 就能绕过。只认文件头，并据此决定落盘扩展名。
     *
     * @return 扩展名，无法识别时返回 null
     */
    private String detectImageExtension(byte[] h) {
        if (h.length >= 3 && (h[0] & 0xFF) == 0xFF && (h[1] & 0xFF) == 0xD8 && (h[2] & 0xFF) == 0xFF) {
            return "jpg";
        }
        if (h.length >= 8
                && (h[0] & 0xFF) == 0x89 && h[1] == 'P' && h[2] == 'N' && h[3] == 'G'
                && (h[4] & 0xFF) == 0x0D && (h[5] & 0xFF) == 0x0A
                && (h[6] & 0xFF) == 0x1A && (h[7] & 0xFF) == 0x0A) {
            return "png";
        }
        // WebP: "RIFF" .... "WEBP"
        if (h.length >= 12
                && h[0] == 'R' && h[1] == 'I' && h[2] == 'F' && h[3] == 'F'
                && h[8] == 'W' && h[9] == 'E' && h[10] == 'B' && h[11] == 'P') {
            return "webp";
        }
        return null;
    }
}
