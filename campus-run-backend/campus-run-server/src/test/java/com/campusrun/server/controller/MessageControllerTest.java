package com.campusrun.server.controller;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.ChatMessageResponse;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.MessageService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = MessageController.class)
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class, GlobalExceptionHandler.class})
class MessageControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private MessageService messageService;

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

    private String token() {
        return jwtTokenProvider.generateToken(1L, "CR-00001234");
    }

    @Test
    void history_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/message/history").param("friendId", "2"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void history_withBeforeId_returns200() throws Exception {
        PageResponse<ChatMessageResponse> page = new PageResponse<>(1, 1, 20, List.of());
        when(messageService.history(any(), any(), any(), anyLong())).thenReturn(page);

        mockMvc.perform(get("/api/v1/message/history")
                        .param("friendId", "2")
                        .param("beforeId", "100")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.total").value(1));
    }

    @Test
    void history_withoutBeforeId_returns200() throws Exception {
        PageResponse<ChatMessageResponse> page = new PageResponse<>(0, 1, 20, List.of());
        when(messageService.history(any(), any(), any(), anyLong())).thenReturn(page);

        mockMvc.perform(get("/api/v1/message/history")
                        .param("friendId", "2")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.total").value(0));
    }

    @Test
    void history_notFriend_returnsFriendNotFound() throws Exception {
        when(messageService.history(any(), any(), any(), anyLong()))
                .thenThrow(new BusinessException(ErrorCode.FRIEND_NOT_FOUND));

        mockMvc.perform(get("/api/v1/message/history")
                        .param("friendId", "999")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(3004));
    }

    @Test
    void markRead_withoutToken_returns401() throws Exception {
        mockMvc.perform(post("/api/v1/message/read").param("messageIds", "100"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void markRead_returnsMarkedCount_forAuthenticatedUser() throws Exception {
        when(messageService.markRead(any(), any())).thenReturn(2);

        mockMvc.perform(post("/api/v1/message/read")
                        .param("messageIds", "100", "101")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data").value(2));

        // 标记对象来自 JWT 中的当前用户，而不是客户端传入的 ID
        verify(messageService).markRead(eq(1L), eq(List.of(100L, 101L)));
    }

    @Test
    void markRead_withoutMessageIds_returnsZero() throws Exception {
        mockMvc.perform(post("/api/v1/message/read")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data").value(0));
    }

    @Test
    void markRead_notReceiver_returns403() throws Exception {
        when(messageService.markRead(any(), any()))
                .thenThrow(new BusinessException(ErrorCode.FORBIDDEN));

        mockMvc.perform(post("/api/v1/message/read")
                        .param("messageIds", "100")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(403));
    }
}
