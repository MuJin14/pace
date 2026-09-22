package com.campusrun.server.controller;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.common.result.PageResponse;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.ActivityCreateResponse;
import com.campusrun.server.dto.response.ActivityDetailResponse;
import com.campusrun.server.dto.response.ActivitySummaryResponse;
import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.ActivityService;
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
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = ActivityController.class)
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class, GlobalExceptionHandler.class})
class ActivityControllerTest {

    private static final String VALID_CREATE_JSON = "{"
            + "\"type\":1,"
            + "\"startTime\":1726992000000,"
            + "\"endTime\":1726995600000,"
            + "\"track\":["
            + "{\"latitude\":39.9,\"longitude\":116.4,\"timestamp\":1726992000000,\"accuracy\":12.5},"
            + "{\"latitude\":39.901,\"longitude\":116.401,\"timestamp\":1726992100000,\"accuracy\":10.0}"
            + "]}";

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private ActivityService activityService;

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
    void create_success() throws Exception {
        ActivityCreateResponse resp = new ActivityCreateResponse();
        resp.setActivityId(1001L);
        resp.setType(1);
        resp.setDistanceMeters(5000);
        when(activityService.create(any(), any())).thenReturn(resp);

        mockMvc.perform(post("/api/v1/activity")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_CREATE_JSON))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.activityId").value(1001))
                .andExpect(jsonPath("$.data.distanceMeters").value(5000));
    }

    @Test
    void create_withoutToken_returns401() throws Exception {
        mockMvc.perform(post("/api/v1/activity")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(VALID_CREATE_JSON))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void create_invalidType_returns400() throws Exception {
        String body = VALID_CREATE_JSON.replace("\"type\":1", "\"type\":3");

        mockMvc.perform(post("/api/v1/activity")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void create_trackTooFewPoints_returns400() throws Exception {
        String body = "{\"type\":1,\"startTime\":1726992000000,\"endTime\":1726995600000,"
                + "\"track\":[{\"latitude\":39.9,\"longitude\":116.4,\"timestamp\":1726992000000,\"accuracy\":12.5}]}";

        mockMvc.perform(post("/api/v1/activity")
                        .header("Authorization", "Bearer " + token())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(body))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(400));
    }

    @Test
    void page_success() throws Exception {
        ActivitySummaryResponse summary = new ActivitySummaryResponse();
        summary.setActivityId(1001L);
        summary.setType(1);
        summary.setDistanceMeters(5000);
        PageResponse<ActivitySummaryResponse> pageResp =
                new PageResponse<>(42L, 1L, 20L, List.of(summary));
        when(activityService.page(any(), any(), anyLong(), anyLong())).thenReturn(pageResp);

        mockMvc.perform(get("/api/v1/activity")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.total").value(42))
                .andExpect(jsonPath("$.data.list[0].activityId").value(1001));
    }

    @Test
    void page_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/activity"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void detail_success() throws Exception {
        ActivityDetailResponse detail = new ActivityDetailResponse();
        detail.setActivityId(1001L);
        detail.setType(1);
        detail.setDistanceMeters(5000);
        detail.setTrack(List.of(new TrackPoint(39.9, 116.4, 1726992000000L, 12.5)));
        when(activityService.getDetail(any(), any())).thenReturn(detail);

        mockMvc.perform(get("/api/v1/activity/1001")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.activityId").value(1001))
                .andExpect(jsonPath("$.data.track[0].latitude").value(39.9));
    }

    @Test
    void detail_forbidden_returns2002() throws Exception {
        when(activityService.getDetail(any(), any()))
                .thenThrow(new BusinessException(ErrorCode.ACTIVITY_FORBIDDEN));

        mockMvc.perform(get("/api/v1/activity/1001")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(2002));
    }

    @Test
    void detail_notFound_returns2001() throws Exception {
        when(activityService.getDetail(any(), any()))
                .thenThrow(new BusinessException(ErrorCode.ACTIVITY_NOT_FOUND));

        mockMvc.perform(get("/api/v1/activity/1001")
                        .header("Authorization", "Bearer " + token()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(2001));
    }

    @Test
    void detail_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/activity/1001"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }
}
