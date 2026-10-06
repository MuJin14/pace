package com.campusrun.server.controller;

import com.campusrun.common.result.Result;
import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RefreshTokenRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.util.ClientIpResolver;
import jakarta.servlet.http.HttpServletRequest;
import jakarta.validation.Valid;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

/**
 * 鉴权接口。Controller 只做转发与取 IP，不含业务逻辑。
 *
 * <p>三个入口都带限流（在 Service 层按「手机号 + IP」双维度计数），
 * 用于阻挡撞库与批量注册。
 */
@RestController
@RequestMapping("/api/v1/auth")
public class AuthController {

    private final AuthService authService;

    public AuthController(AuthService authService) {
        this.authService = authService;
    }

    @PostMapping("/register")
    public Result<LoginResponse> register(@Valid @RequestBody RegisterRequest request,
                                          HttpServletRequest httpRequest) {
        return Result.success(authService.register(request, ClientIpResolver.resolve(httpRequest)));
    }

    @PostMapping("/login")
    public Result<LoginResponse> login(@Valid @RequestBody LoginRequest request,
                                       HttpServletRequest httpRequest) {
        return Result.success(authService.login(request, ClientIpResolver.resolve(httpRequest)));
    }

    /**
     * 用 refresh token 换新的 access token（前端在 401 时自动调用）。
     */
    @PostMapping("/refresh")
    public Result<LoginResponse> refresh(@Valid @RequestBody RefreshTokenRequest request,
                                         HttpServletRequest httpRequest) {
        return Result.success(authService.refresh(request, ClientIpResolver.resolve(httpRequest)));
    }
}
