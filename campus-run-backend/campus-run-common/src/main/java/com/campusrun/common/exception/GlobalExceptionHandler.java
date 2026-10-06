package com.campusrun.common.exception;

import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.Result;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpStatus;
import org.springframework.web.bind.MethodArgumentNotValidException;
import org.springframework.web.bind.annotation.ExceptionHandler;
import org.springframework.web.bind.annotation.ResponseStatus;
import org.springframework.web.bind.annotation.RestControllerAdvice;
import org.springframework.web.servlet.resource.NoResourceFoundException;

@RestControllerAdvice
public class GlobalExceptionHandler {
    private static final Logger log = LoggerFactory.getLogger(GlobalExceptionHandler.class);

    @ExceptionHandler(BusinessException.class)
    public Result<Void> handleBusinessException(BusinessException e) {
        return Result.error(e.getCode(), e.getMessage());
    }

    /**
     * 无权限 → HTTP 403 + body code=403。
     *
     * <p>业务异常默认按 HTTP 200 返回（靠 body 里的 code 区分），这对「参数错误」没问题，
     * 但**权限拒绝必须让 HTTP 状态码也体现出来**：否则调用方无法仅凭状态码区分
     * 「没权限」与「没数据」，前端会把 403 渲染成空态、监控也统计不到越权尝试。
     */
    @ExceptionHandler(ForbiddenException.class)
    @ResponseStatus(HttpStatus.FORBIDDEN)
    public Result<Void> handleForbidden(ForbiddenException e) {
        log.warn("越权访问被拒绝: {}", e.getMessage());
        return Result.error(ErrorCode.FORBIDDEN.getCode(), e.getMessage());
    }

    @ExceptionHandler(MethodArgumentNotValidException.class)
    public Result<Void> handleValidation(MethodArgumentNotValidException e) {
        String message = e.getBindingResult().getFieldErrors().stream()
                .findFirst()
                .map(f -> f.getDefaultMessage())
                .orElse(ErrorCode.PARAM_ERROR.getMessage());
        return Result.error(ErrorCode.PARAM_ERROR.getCode(), message);
    }

    /**
     * 路径不存在 → 404。
     *
     * <p>此前这里会被下面的 {@code Exception} 兜底吞掉，返回 **HTTP 200 + body code=500**，
     * 造成两个后果：调用方按 HTTP 状态码判断会以为请求成功；排查时又会看到
     * 「服务器内部错误」，把「路径写错」误导成「服务端故障」。
     */
    @ExceptionHandler(NoResourceFoundException.class)
    @ResponseStatus(HttpStatus.NOT_FOUND)
    public Result<Void> handleNoResource(NoResourceFoundException e) {
        // 客户端错误，用 warn 而非 error，避免污染服务端错误告警
        log.warn("请求路径不存在: {}", e.getResourcePath());
        return Result.error(ErrorCode.NOT_FOUND);
    }

    @ExceptionHandler(Exception.class)
    public Result<Void> handleException(Exception e) {
        log.error("Unexpected error", e);
        return Result.error(ErrorCode.INTERNAL_ERROR);
    }
}
