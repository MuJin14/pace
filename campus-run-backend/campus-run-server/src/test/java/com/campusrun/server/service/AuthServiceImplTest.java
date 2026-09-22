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
        when(jwtTokenProvider.generateToken(any(), any())).thenReturn("token-1");

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
        when(jwtTokenProvider.generateToken(1L, "CR-00001234")).thenReturn("token-1");

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
}
