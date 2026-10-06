package com.campusrun.common.exception;

/**
 * 无权限访问。
 *
 * <p>与 {@link BusinessException} 的区别在于 **HTTP 状态码**：
 * 业务异常统一按 HTTP 200 + body `code` 返回（前端按 code 判错），
 * 而权限拒绝需要让状态码本身是 403 —— 这样调用方仅凭状态码就能区分
 * 「没权限」与「对方没数据」，前端不会把 403 渲染成空态，
 * 监控也能统计到越权尝试。
 *
 * <p>单独定义而不是用 Spring Security 的 {@code AccessDeniedException}：
 * 本模块（campus-run-common）不依赖 spring-security，不应为了一个异常引入该依赖。
 */
public class ForbiddenException extends RuntimeException {

    public ForbiddenException(String message) {
        super(message);
    }
}
