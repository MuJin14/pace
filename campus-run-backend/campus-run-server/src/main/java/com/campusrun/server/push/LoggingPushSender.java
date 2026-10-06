package com.campusrun.server.push;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.boot.autoconfigure.condition.ConditionalOnProperty;
import org.springframework.stereotype.Component;

import java.util.Map;

/**
 * 开发用推送实现：只写日志，不真的发通知。
 *
 * <p>为什么要有它：离线推送依赖 Firebase 凭证，而凭证不该进仓库。
 * 没有凭证时如果直接抛异常或静默失败，会导致「功能看起来没写」或
 * 「一调用就报错」。这个实现把内容完整打出来，使**整条推送链路
 * （取令牌 → 组装文案 → 失败清理）都能被测试和肉眼验证**。
 *
 * <p>配置真实凭证后本实现自动失效（见 {@code app.push.enabled}）。
 */
@Component
@ConditionalOnProperty(name = "app.push.enabled", havingValue = "false", matchIfMissing = true)
public class LoggingPushSender implements PushSender {

    private static final Logger log = LoggerFactory.getLogger(LoggingPushSender.class);

    @Override
    public Result send(String token, String title, String body, Map<String, String> data) {
        // 令牌只打尾部，避免日志里出现可用于推送的完整凭据
        String masked = token == null || token.length() <= 8
                ? "***"
                : "***" + token.substring(token.length() - 8);
        log.info("[PUSH-DEV] token={} title=\"{}\" body=\"{}\" data={}",
                masked, title, body, data);
        return Result.NOT_CONFIGURED;
    }

    @Override
    public boolean isConfigured() {
        return false;
    }
}
