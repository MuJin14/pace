package com.campusrun.server.util;

import jakarta.servlet.http.HttpServletRequest;

/**
 * 解析真实客户端 IP，供限流使用。
 *
 * <p>为什么不能直接用 {@code request.getRemoteAddr()}：生产环境通常部署在 Nginx 之后，
 * 此时 remoteAddr 恒为反向代理的地址，所有用户会共用一个限流配额——既挡不住攻击者，
 * 又会误伤正常用户。
 *
 * <p>因此按「X-Forwarded-For 最左值 → X-Real-IP → remoteAddr」的优先级取，
 * 并在无法解析时返回 {@code unknown}（限流会退化为「全局共享一个配额」，
 * 属于 fail-safe 方向：宁可整体收紧，也不要完全放开）。
 *
 * <p><b>安全前提</b>：只有在受信任的反向代理后面才应信任 X-Forwarded-For，
 * 否则客户端可以自行伪造该头绕过限流。部署时必须保证应用端口不直接暴露公网。
 */
public final class ClientIpResolver {

    private static final String UNKNOWN = "unknown";

    private ClientIpResolver() {
    }

    public static String resolve(HttpServletRequest request) {
        if (request == null) {
            return UNKNOWN;
        }
        String forwarded = request.getHeader("X-Forwarded-For");
        if (forwarded != null && !forwarded.isBlank()) {
            // X-Forwarded-For 可能是逗号分隔链：client, proxy1, proxy2
            int comma = forwarded.indexOf(',');
            String first = (comma > 0 ? forwarded.substring(0, comma) : forwarded).trim();
            if (!first.isEmpty() && !"unknown".equalsIgnoreCase(first)) {
                return first;
            }
        }
        String realIp = request.getHeader("X-Real-IP");
        if (realIp != null && !realIp.isBlank()) {
            return realIp.trim();
        }
        String remote = request.getRemoteAddr();
        return (remote == null || remote.isBlank()) ? UNKNOWN : remote;
    }
}
