package com.campusrun.server.controller;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.FriendItemResponse;
import com.campusrun.server.dto.response.UserBriefResponse;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.FriendService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.context.TestConfiguration;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Import;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.List;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.Mockito.doThrow;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = FriendController.class)
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class, GlobalExceptionHandler.class})
class FriendControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private FriendService friendService;

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
    void search_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/friend/search").param("keyword", "乙"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void search_success() throws Exception {
        UserBriefResponse user = new UserBriefResponse();
        user.setUserId(2L);
        user.setUniqueId("CR-00000002");
        user.setNickname("乙");
        PageResponse<UserBriefResponse> page = new PageResponse<>(1L, 1L, 20L, List.of(user));
        when(friendService.search(any(), anyString(), anyLong(), anyLong())).thenReturn(page);

        mockMvc.perform(get("/api/v1/friend/search")
                        .param("keyword", "乙")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.list[0].userId").value(2));
    }

    @Test
    void sendRequest_success() throws Exception {
        mockMvc.perform(post("/api/v1/friend/request")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUserId\":2}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void sendRequest_cannotFriendSelf_returns3003() throws Exception {
        doThrow(new BusinessException(ErrorCode.CANNOT_FRIEND_SELF))
                .when(friendService).sendRequest(any(), any());

        mockMvc.perform(post("/api/v1/friend/request")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"targetUserId\":1}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(3003));
    }

    @Test
    void acceptRequest_success() throws Exception {
        mockMvc.perform(post("/api/v1/friend/accept")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content("{\"requestId\":100}"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void friendList_success() throws Exception {
        FriendItemResponse friend = new FriendItemResponse();
        friend.setFriendshipId(1L);
        friend.setUserId(2L);
        friend.setNickname("乙");
        when(friendService.friendList(any())).thenReturn(List.of(friend));

        mockMvc.perform(get("/api/v1/friend/list")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data[0].userId").value(2));
    }

    @Test
    void deleteFriend_success() throws Exception {
        mockMvc.perform(delete("/api/v1/friend/2")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    @Test
    void deleteFriend_notFriend_returns3004() throws Exception {
        doThrow(new BusinessException(ErrorCode.FRIEND_NOT_FOUND))
                .when(friendService).deleteFriend(any(), any());

        mockMvc.perform(delete("/api/v1/friend/2")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(3004));
    }
}
