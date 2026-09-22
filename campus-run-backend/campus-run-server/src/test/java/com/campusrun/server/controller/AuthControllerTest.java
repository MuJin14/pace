package com.campusrun.server.controller;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.LoginResponse;
import com.campusrun.server.dto.response.UserInfoResponse;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.AuthService;
import com.campusrun.server.service.UserService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = {AuthController.class, UserController.class})
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class, GlobalExceptionHandler.class})
class AuthControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private AuthService authService;

    @MockBean
    private UserService userService;

    @TestConfiguration
    static class TestConfig {
        @Bean
        JwtProperties jwtProperties() {
            JwtProperties properties = new JwtProperties();
            properties.setSecret("test-secret-key-for-jwt-that-is-long-enough-1234567890");
            properties.setExpiration(3600L);
            return properties;
        }
    }

    @Test
    void register_success() throws Exception {
        LoginResponse response = new LoginResponse();
        response.setToken("token-1");
        response.setUserId(1L);
        response.setUniqueId("CR-00001234");
        response.setNickname("小明");
        response.setPhone("13800138000");
        when(authService.register(any())).thenReturn(response);

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800138000\",\"password\":\"secret123\",\"nickname\":\"小明\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.token").value("token-1"))
                .andExpect(jsonPath("$.data.uniqueId").value("CR-00001234"));
    }

    @Test
    void register_duplicatePhone_returnsPhoneExists() throws Exception {
        when(authService.register(any())).thenThrow(new BusinessException(ErrorCode.PHONE_EXISTS));

        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800138000\",\"password\":\"secret123\",\"nickname\":\"小明\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(1001));
    }

    @Test
    void register_invalidPhone_returnsParamError() throws Exception {
        mockMvc.perform(post("/api/v1/auth/register")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"123\",\"password\":\"secret123\",\"nickname\":\"小明\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void login_success() throws Exception {
        LoginResponse response = new LoginResponse();
        response.setToken("token-1");
        response.setUserId(1L);
        response.setUniqueId("CR-00001234");
        when(authService.login(any())).thenReturn(response);

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800138000\",\"password\":\"secret123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.token").value("token-1"));
    }

    @Test
    void login_wrongPassword_returnsPasswordError() throws Exception {
        when(authService.login(any())).thenThrow(new BusinessException(ErrorCode.PASSWORD_ERROR));

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800138000\",\"password\":\"wrong\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(1003));
    }

    @Test
    void login_userNotFound_returnsUserNotFound() throws Exception {
        when(authService.login(any())).thenThrow(new BusinessException(ErrorCode.USER_NOT_FOUND));

        mockMvc.perform(post("/api/v1/auth/login")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"phone\":\"13800138000\",\"password\":\"secret123\"}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(1002));
    }

    @Test
    void me_withValidToken_returnsUserInfo() throws Exception {
        UserInfoResponse info = new UserInfoResponse();
        info.setUserId(1L);
        info.setUniqueId("CR-00001234");
        info.setNickname("小明");
        info.setPhone("13800138000");
        when(userService.getCurrentUser(1L)).thenReturn(info);

        String token = jwtTokenProvider.generateToken(1L, "CR-00001234");

        mockMvc.perform(get("/api/v1/user/me").header("Authorization", "Bearer " + token))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.uniqueId").value("CR-00001234"))
                .andExpect(jsonPath("$.data.nickname").value("小明"));
    }

    @Test
    void me_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/user/me"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }
}
