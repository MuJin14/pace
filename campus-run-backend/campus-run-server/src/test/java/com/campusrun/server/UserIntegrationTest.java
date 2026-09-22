package com.campusrun.server;

import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.service.AuthService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;

import java.util.regex.Pattern;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
@ActiveProfiles("test")
class UserIntegrationTest {

    private static final Pattern UNIQUE_ID_PATTERN = Pattern.compile("^CR-\\d{8}$");
    private static final String PHONE = "13800138000";
    private static final String PASSWORD = "secret123";

    @Autowired
    private AuthService authService;

    @Autowired
    private UserMapper userMapper;

    @Test
    void registerAndLogin_closedLoop() {
        // 1. 注册写入 H2
        RegisterRequest registerRequest = new RegisterRequest();
        registerRequest.setPhone(PHONE);
        registerRequest.setPassword(PASSWORD);
        registerRequest.setNickname("小明");

        LoginResponse registerResponse = authService.register(registerRequest);
        assertNotNull(registerResponse);
        assertNotNull(registerResponse.getToken());
        Long userId = registerResponse.getUserId();
        assertNotNull(userId);

        // 2. 通过 UserMapper 查询验证
        User user = userMapper.selectById(userId);
        assertNotNull(user);
        assertEquals(PHONE, user.getPhone());
        assertEquals("小明", user.getNickname());
        assertTrue(UNIQUE_ID_PATTERN.matcher(user.getUniqueId()).matches(), "专属 ID 应为 CR-XXXXXXXX 格式");
        assertNotEquals(PASSWORD, user.getPasswordHash(), "密码应为密文，非明文");
        assertTrue(user.getPasswordHash().startsWith("$2"), "密码应为 BCrypt 密文（$2 开头）");

        // 3. 模拟登录，验证密码比对
        LoginRequest loginRequest = new LoginRequest();
        loginRequest.setPhone(PHONE);
        loginRequest.setPassword(PASSWORD);

        LoginResponse loginResponse = authService.login(loginRequest);
        assertNotNull(loginResponse);
        assertEquals(userId, loginResponse.getUserId());
        assertEquals(user.getUniqueId(), loginResponse.getUniqueId());
        assertNotNull(loginResponse.getToken());
    }
}
