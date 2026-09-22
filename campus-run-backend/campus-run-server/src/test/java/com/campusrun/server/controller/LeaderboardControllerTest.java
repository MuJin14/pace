package com.campusrun.server.controller;

import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.LeaderboardEntryResponse;
import com.campusrun.server.dto.response.MyRankResponse;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.LeaderboardService;
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
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = LeaderboardController.class)
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class, GlobalExceptionHandler.class})
class LeaderboardControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private LeaderboardService leaderboardService;

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
    void board_success() throws Exception {
        LeaderboardEntryResponse entry = new LeaderboardEntryResponse();
        entry.setRank(1L);
        entry.setUserId(3L);
        entry.setUniqueId("CR-00000003");
        entry.setNickname("小明");
        entry.setDistanceMeters(15230);
        PageResponse<LeaderboardEntryResponse> pageResp =
                new PageResponse<>(128L, 1L, 20L, List.of(entry));
        when(leaderboardService.getBoard(any(), any(), any(), anyLong(), anyLong())).thenReturn(pageResp);

        mockMvc.perform(get("/api/v1/leaderboard")
                        .header("Authorization", "Bearer " + token())
                        .param("scope", "daily")
                        .param("period", "2026-09-22")
                        .param("type", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.total").value(128))
                .andExpect(jsonPath("$.data.list[0].rank").value(1))
                .andExpect(jsonPath("$.data.list[0].distanceMeters").value(15230));
    }

    @Test
    void board_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/leaderboard")
                        .param("scope", "daily")
                        .param("type", "1"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void myRank_success() throws Exception {
        MyRankResponse my = new MyRankResponse(7L, 5200L, 128L);
        when(leaderboardService.getMyRank(any(), any(), any(), any())).thenReturn(my);

        mockMvc.perform(get("/api/v1/leaderboard/my-rank")
                        .header("Authorization", "Bearer " + token())
                        .param("scope", "daily")
                        .param("type", "1"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.rank").value(7))
                .andExpect(jsonPath("$.data.distanceMeters").value(5200));
    }

    @Test
    void myRank_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/leaderboard/my-rank")
                        .param("scope", "daily")
                        .param("type", "1"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }
}
