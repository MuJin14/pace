package com.campusrun.server.service;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.dto.request.LoginRequest;
import com.campusrun.server.dto.request.RegisterRequest;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.entity.User;
import com.campusrun.server.mapper.UserMapper;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.impl.AuthServiceImpl;
import com.campusrun.server.util.UniqueIdGenerator;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.junit.jupiter.api.extension.ExtendWith;
import org.mockito.ArgumentCaptor;
import org.mockito.Mock;
import org.mockito.junit.jupiter.MockitoExtension;
import org.springframework.security.crypto.password.PasswordEncoder;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertNotEquals;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyInt;
import static org.mockito.Mockito.doAnswer;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;

@ExtendWith(MockitoExtension.class)
class AuthServiceImplTest {

    @Mock
    private UserMapper userMapper;
    @Mock
    private PasswordEncoder passwordEncoder;
    @Mock
    private JwtTokenProvider jwtTokenProvider;
    @Mock
    private UniqueIdGenerator uniqueIdGenerator;

    private AuthServiceImpl authService;

    @BeforeEach
    void setUp() {
        authService = new AuthServiceImpl(userMapper, passwordEncoder, jwtTokenProvider, uniqueIdGenerator);
    }

    @Test
    void register_success() {
        RegisterRequest request = new RegisterRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");
        request.setNickname("小明");

        when(userMapper.selectCount(any())).thenReturn(0L);
        when(uniqueIdGenerator.generate(userMapper)).thenReturn("CR-00001234");
        when(passwordEncoder.encode("secret123")).thenReturn("hashed-password");
        when(jwtTokenProvider.generateAccessToken(any(), any(), any(), anyInt())).thenReturn("token-1");
        when(jwtTokenProvider.generateRefreshToken(any(), any(), any(), anyInt())).thenReturn("refresh-1");

        doAnswer(invocation -> {
            User u = invocation.getArgument(0);
            u.setId(100L);
            return 1;
        }).when(userMapper).insert(any(User.class));

        LoginResponse response = authService.register(request);

        assertNotNull(response);
        assertEquals("token-1", response.getToken());
        assertEquals(100L, response.getUserId());
        assertEquals("CR-00001234", response.getUniqueId());
        assertEquals("13800138000", response.getPhone());

        ArgumentCaptor<User> captor = ArgumentCaptor.forClass(User.class);
        verify(userMapper).insert(captor.capture());
        User saved = captor.getValue();
        assertEquals("hashed-password", saved.getPasswordHash());
        assertNotEquals("secret123", saved.getPasswordHash());
    }

    @Test
    void register_duplicatePhone_throwsBusinessException() {
        RegisterRequest request = new RegisterRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");
        request.setNickname("小明");

        when(userMapper.selectCount(any())).thenReturn(1L);

        BusinessException ex = assertThrows(BusinessException.class, () -> authService.register(request));
        assertEquals(ErrorCode.PHONE_EXISTS.getCode(), ex.getCode());
    }

    @Test
    void login_success() {
        User user = new User();
        user.setId(1L);
        user.setPhone("13800138000");
        user.setPasswordHash("hashed");
        user.setUniqueId("CR-00001234");
        user.setNickname("小明");

        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);
        when(jwtTokenProvider.generateAccessToken(any(), any(), any(), anyInt())).thenReturn("token-1");
        when(jwtTokenProvider.generateRefreshToken(any(), any(), any(), anyInt())).thenReturn("refresh-1");

        LoginRequest request = new LoginRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");

        LoginResponse response = authService.login(request);

        assertEquals("token-1", response.getToken());
        assertEquals(1L, response.getUserId());
        assertEquals("CR-00001234", response.getUniqueId());
    }

    @Test
    void login_userNotFound_throwsBusinessException() {
        when(userMapper.selectOne(any())).thenReturn(null);

        LoginRequest request = new LoginRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");

        BusinessException ex = assertThrows(BusinessException.class, () -> authService.login(request));
        assertEquals(ErrorCode.USER_NOT_FOUND.getCode(), ex.getCode());
    }

    @Test
    void login_wrongPassword_throwsBusinessException() {
        User user = new User();
        user.setId(1L);
        user.setPhone("13800138000");
        user.setPasswordHash("hashed");
        user.setUniqueId("CR-00001234");

        when(userMapper.selectOne(any())).thenReturn(user);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(false);

        LoginRequest request = new LoginRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");

        BusinessException ex = assertThrows(BusinessException.class, () -> authService.login(request));
        assertEquals(ErrorCode.PASSWORD_ERROR.getCode(), ex.getCode());
    }

    /**
     * 登录响应必须带上 role。
     *
     * <p>真实故障：登录响应漏了 role 字段，App 的 {@code User.fromJson} 用
     * {@code json['role'] ?? 0} 解析，于是管理员登录后 role 变成 0，
     * 「管理后台」入口不显示 —— 用户看到的现象是「升级后管理员权限没了」。
     * 只有等 {@code /user/me} 返回后才恢复，中间那段时间入口是消失的。
     */
    @Test
    void login_responseCarriesRole_forAdmin() {
        User admin = new User();
        admin.setId(1L);
        admin.setPhone("13800138000");
        admin.setPasswordHash("hashed");
        admin.setUniqueId("CR-00001234");
        admin.setNickname("管理员");
        admin.setRole(1);

        when(userMapper.selectOne(any())).thenReturn(admin);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);
        when(jwtTokenProvider.generateAccessToken(any(), any(), any(), anyInt())).thenReturn("token-1");
        when(jwtTokenProvider.generateRefreshToken(any(), any(), any(), anyInt())).thenReturn("refresh-1");

        LoginRequest request = new LoginRequest();
        request.setPhone("13800138000");
        request.setPassword("secret123");

        LoginResponse response = authService.login(request);

        assertNotNull(response.getRole(), "登录响应必须包含 role，否则 App 会把管理员当成普通用户");
        assertEquals(1, response.getRole());
    }

    @Test
    void login_responseCarriesRole_forNormalUser() {
        User normal = new User();
        normal.setId(2L);
        normal.setPhone("13900139000");
        normal.setPasswordHash("hashed");
        normal.setUniqueId("CR-00005678");
        normal.setRole(0);

        when(userMapper.selectOne(any())).thenReturn(normal);
        when(passwordEncoder.matches("secret123", "hashed")).thenReturn(true);
        when(jwtTokenProvider.generateAccessToken(any(), any(), any(), anyInt())).thenReturn("token-2");
        when(jwtTokenProvider.generateRefreshToken(any(), any(), any(), anyInt())).thenReturn("refresh-2");

        LoginRequest request = new LoginRequest();
        request.setPhone("13900139000");
        request.setPassword("secret123");

        LoginResponse response = authService.login(request);

        assertEquals(0, response.getRole(), "普通用户应当是 0，不能漏字段也不能误判为管理员");
    }
}
