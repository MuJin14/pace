package com.campusrun.server.push;

import com.baomidou.mybatisplus.core.conditions.query.LambdaQueryWrapper;
import com.campusrun.server.entity.DeviceToken;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.DeviceTokenMapper;
import com.campusrun.server.mapper.UserMapper;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.stereotype.Service;

import java.util.HashMap;
import java.util.List;
import java.util.Map;

/**
 * 离线推送：设备令牌管理 + 发通知。
 *
 * <p>设计取舍：
 * <ul>
 *   <li>**只推给收件人的设备**，绝不推给发送者自己 —— 否则用户给自己发的消息
 *       会在自己手机上弹通知（WebSocket 已在本机显示过了）。</li>
 *   <li>推送失败**绝不能影响消息发送**：消息已落库，推送只是尽力而为的增强，
 *       所以这里整体吞掉异常并记日志。</li>
 *   <li>令牌失效要删掉，临时故障要保留 —— 删错会让用户永远收不到通知。</li>
 * </ul>
 */
@Service
public class PushService {

    private static final Logger log = LoggerFactory.getLogger(PushService.class);

    private static final String CHANNEL_ID = "messages";
    private static final int MAX_PREVIEW = 50;

    private final DeviceTokenMapper deviceTokenMapper;
    private final UserMapper userMapper;
    private final PushSender pushSender;

    public PushService(DeviceTokenMapper deviceTokenMapper,
                       UserMapper userMapper,
                       PushSender pushSender) {
        this.deviceTokenMapper = deviceTokenMapper;
        this.userMapper = userMapper;
        this.pushSender = pushSender;
    }

    /**
     * 注册（或改归属）设备令牌。
     *
     * @param userId   当前登录用户
     * @param token    FCM 令牌
     * @param platform android / ios / web
     */
    public void register(Long userId, String token, String platform) {
        deviceTokenMapper.upsert(userId, token, platform == null ? "android" : platform);
        log.debug("设备令牌已登记: userId={} platform={}", userId, platform);
    }

    /** 登出时注销令牌，避免用户登出后仍收到该账号的通知。 */
    public void unregister(String token) {
        if (token == null || token.isBlank()) {
            return;
        }
        deviceTokenMapper.deleteByToken(token);
    }

    /**
     * 给某个用户的所有设备推送一条消息通知。
     *
     * <p>异步调用方负责不阻塞业务；本方法自身不抛异常。
     *
     * @param receiverId     收件人
     * @param senderNickname 发件人昵称（做成标题，让用户一眼知道是谁）
     * @param content        消息正文（用于通知预览）
     * @param messageId      消息 id（客户端点击通知后跳转到对应会话）
     */
    public void pushMessage(Long receiverId, String senderNickname, String content, Long messageId) {
        try {
            List<DeviceToken> tokens = deviceTokenMapper.selectByUserId(receiverId);
            if (tokens.isEmpty()) {
                log.debug("收件人 userId={} 没有登记设备，跳过推送", receiverId);
                return;
            }

            String title = (senderNickname == null || senderNickname.isBlank())
                    ? "新消息"
                    : senderNickname;
            String body = preview(content);

            Map<String, String> data = new HashMap<>();
            data.put("type", "message");
            data.put("route", "/friends");
            // FCM 的 data 值必须是字符串
            data.put("messageId", String.valueOf(messageId));
            data.put("channelId", CHANNEL_ID);

            int sent = 0;
            for (DeviceToken device : tokens) {
                PushSender.Result result =
                        pushSender.send(device.getToken(), title, body, data);
                switch (result) {
                    case SUCCESS -> sent++;
                    case INVALID_TOKEN -> {
                        // 令牌失效：清掉，否则每次发消息都白推一次
                        deviceTokenMapper.deleteByToken(device.getToken());
                        log.info("清理失效的设备令牌: userId={}", receiverId);
                    }
                    case RETRYABLE_FAILURE ->
                            log.warn("推送临时失败，保留令牌: userId={}", receiverId);
                    case NOT_CONFIGURED ->
                            log.debug("未配置推送凭证，仅记录日志（开发模式）");
                }
            }
            log.debug("推送完成: receiverId={} 设备数={} 成功={}", receiverId, tokens.size(), sent);
        } catch (Exception e) {
            // 推送是增强能力：任何异常都不能影响消息发送本身
            log.warn("推送失败（不影响消息投递）: receiverId={} err={}", receiverId, e.getMessage());
        }
    }

    /**
     * 通知正文：截断过长内容。
     *
     * <p>按**码点**截断而不是按 UTF-16 长度，否则中文/emoji 会被截成半个字符
     * （emoji 常占 2 个 char，截一半会显示成乱码方块）。
     */
    private String preview(String content) {
        if (content == null) {
            return "";
        }
        String flat = content.replaceAll("\\s+", " ").trim();
        int codePoints = flat.codePointCount(0, flat.length());
        if (codePoints <= MAX_PREVIEW) {
            return flat;
        }
        int end = flat.offsetByCodePoints(0, MAX_PREVIEW);
        return flat.substring(0, end) + "…";
    }

    /** 供测试与调试：查询某用户已登记的令牌数。 */
    public long countDevices(Long userId) {
        Long n = deviceTokenMapper.selectCount(new LambdaQueryWrapper<DeviceToken>()
                .eq(DeviceToken::getUserId, userId));
        return n == null ? 0 : n;
    }

    /** 查昵称，取不到时返回 null（由调用方给兜底标题）。 */
    public String nicknameOf(Long userId) {
        if (userId == null) {
            return null;
        }
        User user = userMapper.selectById(userId);
        return user == null ? null : user.getNickname();
    }
}
