package com.campusrun.server.service;

import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RefreshTokenRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;

public interface AuthService {

    /**
     * 注册新用户：生成专属 ID 并签发 JWT。
     *
     * @param request  注册请求（手机号、密码、昵称）
     * @param clientIp 调用方 IP，用于登录/注册限流
     * @return 登录态（access token + refresh token + 用户信息）
     * @throws BusinessException 手机号已注册 / 触发限流
     */
    LoginResponse register(RegisterRequest request, String clientIp);

    /**
     * 手机号 + 密码登录，签发 JWT。
     *
     * @param request  登录请求（手机号、密码）
     * @param clientIp 调用方 IP，用于登录/注册限流
     * @return 登录态（access token + refresh token + 用户信息）
     * @throws BusinessException 用户不存在、密码错误或触发限流
     */
    LoginResponse login(LoginRequest request, String clientIp);

    /**
     * 用 refresh token 换新的 access token。
     *
     * <p>refresh token 必须是 {@code typ=refresh} 的令牌；access token 与伪造令牌一律拒绝。
     * 用户被删除后其 refresh token 也不再可用（会重新查库校验）。
     *
     * @param request  刷新请求（refreshToken）
     * @param clientIp 调用方 IP，用于限流
     * @return 新的登录态（新的 access token，refresh token 原样返回）
     * @throws BusinessException 刷新令牌无效/过期，或触发限流
     */
    LoginResponse refresh(RefreshTokenRequest request, String clientIp);

    /**
     * 兼容重载：不限 IP（仅按手机号维度限流）。
     *
     * <p>保留它是为了不强迫所有内部调用方/测试都感知 IP 维度；
     * HTTP 入口 {@code AuthController} 一律使用带 clientIp 的重载。
     */
    default LoginResponse register(RegisterRequest request) {
        return register(request, null);
    }

    /** 兼容重载：不限 IP（仅按手机号维度限流）。 */
    default LoginResponse login(LoginRequest request) {
        return login(request, null);
    }
}
