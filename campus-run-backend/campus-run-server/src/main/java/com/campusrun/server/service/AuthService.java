package com.campusrun.server.service;

import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;

public interface AuthService {

    /**
     * 注册新用户：生成专属 ID 并签发 JWT。
     *
     * @param request 注册请求（手机号、密码、昵称）
     * @return 登录态（token + 用户信息）
     * @throws BusinessException 手机号已注册
     */
    LoginResponse register(RegisterRequest request);

    /**
     * 手机号 + 密码登录，签发 JWT。
     *
     * @param request 登录请求（手机号、密码）
     * @return 登录态（token + 用户信息）
     * @throws BusinessException 用户不存在或密码错误
     */
    LoginResponse login(LoginRequest request);
}
