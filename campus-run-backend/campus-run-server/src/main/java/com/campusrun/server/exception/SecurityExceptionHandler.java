package com.campusrun.server.exception;

import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.Result;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.security.access.AccessDeniedException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;

/**
 * 处理 Spring Security 的权限拒绝。
 *
 * <p><b>为什么必须有 {@code @ResponseStatus(FORBIDDEN)}（真实 bug）</b>：
 * 这个处理器最初只写了 `return Result.error(FORBIDDEN)`，**漏了状态码注解**，
 * 于是 `@PreAuthorize` 拒绝时实际返回 **HTTP 200 + body `{code:403}`**。
 *
 * <p>后果与项目文档里记载的 `ForbiddenException` 问题完全同类：
 * 调用方<b>无法仅凭状态码</b>区分「没权限」与「查到了但没数据」，
 * 前端 `catch` 不到（不抛异常），会把越权直接渲染成空态；
 * 监控与日志也统计不到越权尝试。
 * 项目早已为「业务层权限拒绝」引入了带 `@ResponseStatus` 的
 * `ForbiddenException`，却漏了 Security 自己抛的这一种。
 *
 * <p>回归由 `AdminAccessControlTest`（HTTP 层，8 个用例）固化：
 * 普通用户必须 **403**、匿名必须 401、管理员必须 200。
 */
@RestControllerAdvice
public class SecurityExceptionHandler {

    private static final Logger log = LoggerFactory.getLogger(SecurityExceptionHandler.class);

    @ExceptionHandler(AccessDeniedException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public Result<Void> handleAccessDenied(AccessDeniedException e) {
        // 越权尝试值得留痕（能发现被扫描的接口），但不是服务端故障，用 warn
        log.warn("权限不足被拒绝: {}", e.getMessage());
        return Result.error(ErrorCode.FORBIDDEN);
    }
}
