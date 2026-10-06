package com.campusrun.server.controller;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.common.exception.GlobalExceptionHandler;
import com.campusrun.common.result.ErrorCode;
import com.campusrun.server.config.JwtProperties;
import com.campusrun.server.config.SecurityConfig;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.exception.SecurityExceptionHandler;
import com.campusrun.server.security.JwtAuthenticationFilter;
import com.campusrun.server.security.JwtTokenProvider;
import com.campusrun.server.service.FenceService;
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
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.delete;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.put;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(controllers = FenceController.class)
@Import({SecurityConfig.class, JwtAuthenticationFilter.class, JwtTokenProvider.class,
        GlobalExceptionHandler.class, SecurityExceptionHandler.class})
class FenceControllerTest {

    @Autowired
    private MockMvc mockMvc;

    @Autowired
    private JwtTokenProvider jwtTokenProvider;

    @MockBean
    private FenceService fenceService;

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

    private String userToken() {
        return jwtTokenProvider.generateToken(1L, "CR-00001234");
    }

    private String adminToken() {
        return jwtTokenProvider.generateToken(1L, "CR-00001234", 1);
    }

    private FenceResponse fenceResponse() {
        FenceResponse response = new FenceResponse();
        response.setId(1L);
        response.setName("操场");
        response.setEnabled(1);
        return response;
    }

    private String fenceBody() {
        return "{\"name\":\"操场\",\"centerLat\":39.9,\"centerLng\":116.4,\"radiusMeters\":100}";
    }

    // ---- list ----

    @Test
    void list_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/admin/fences"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void list_withUserToken_returns403() throws Exception {
        mockMvc.perform(get("/api/v1/admin/fences")
                        .header("Authorization", "Bearer " + userToken()))
                // 权限拒绝必须是 HTTP 403 本身，而不是 200 + body code=403。
                // 原来断言 status().isOk() 等于把缺陷固化成了期望；
                // 前端只按状态码判断时，200 会让它把「没权限」渲染成空态。
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void list_withAdminToken_returns200() throws Exception {
        when(fenceService.list()).thenReturn(List.of());

        mockMvc.perform(get("/api/v1/admin/fences")
                        .header("Authorization", "Bearer " + adminToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }

    // ---- get ----

    @Test
    void get_withoutToken_returns401() throws Exception {
        mockMvc.perform(get("/api/v1/admin/fences/1"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void get_withUserToken_returns403() throws Exception {
        mockMvc.perform(get("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + userToken()))
                // 权限拒绝必须是 HTTP 403 本身，而不是 200 + body code=403。
                // 原来断言 status().isOk() 等于把缺陷固化成了期望；
                // 前端只按状态码判断时，200 会让它把「没权限」渲染成空态。
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void get_withAdminToken_returns200() throws Exception {
        when(fenceService.get(1L)).thenReturn(fenceResponse());

        mockMvc.perform(get("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + adminToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.id").value(1))
                .andExpect(jsonPath("$.data.name").value("操场"));
    }

    @Test
    void get_notFound_returnsFenceNotFound() throws Exception {
        when(fenceService.get(1L)).thenThrow(new BusinessException(ErrorCode.FENCE_NOT_FOUND));

        mockMvc.perform(get("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + adminToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(5001));
    }

    // ---- create ----

    @Test
    void create_withoutToken_returns401() throws Exception {
        mockMvc.perform(post("/api/v1/admin/fences")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void create_withUserToken_returns403() throws Exception {
        mockMvc.perform(post("/api/v1/admin/fences")
                        .header("Authorization", "Bearer " + userToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                // 权限拒绝必须是 HTTP 403 本身，而不是 200 + body code=403。
                // 原来断言 status().isOk() 等于把缺陷固化成了期望；
                // 前端只按状态码判断时，200 会让它把「没权限」渲染成空态。
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void create_withAdminToken_returns200() throws Exception {
        when(fenceService.create(any())).thenReturn(fenceResponse());

        mockMvc.perform(post("/api/v1/admin/fences")
                        .header("Authorization", "Bearer " + adminToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.id").value(1));
    }

    @Test
    void create_invalidLat_returnsParamError() throws Exception {
        String invalid = "{\"name\":\"操场\",\"centerLat\":999.0,\"centerLng\":116.4,\"radiusMeters\":100}";

        mockMvc.perform(post("/api/v1/admin/fences")
                        .header("Authorization", "Bearer " + adminToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(invalid))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(400));
    }

    // ---- update ----

    @Test
    void update_withoutToken_returns401() throws Exception {
        mockMvc.perform(put("/api/v1/admin/fences/1")
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void update_withUserToken_returns403() throws Exception {
        mockMvc.perform(put("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + userToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                // 权限拒绝必须是 HTTP 403 本身，而不是 200 + body code=403。
                // 原来断言 status().isOk() 等于把缺陷固化成了期望；
                // 前端只按状态码判断时，200 会让它把「没权限」渲染成空态。
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void update_withAdminToken_returns200() throws Exception {
        when(fenceService.update(eq(1L), any())).thenReturn(fenceResponse());

        mockMvc.perform(put("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + adminToken())
                        .contentType(MediaType.APPLICATION_JSON)
                        .content(fenceBody()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0))
                .andExpect(jsonPath("$.data.id").value(1));
    }

    // ---- disable ----

    @Test
    void disable_withoutToken_returns401() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/fences/1"))
                .andExpect(status().isUnauthorized())
                .andExpect(jsonPath("$.code").value(401));
    }

    @Test
    void disable_withUserToken_returns403() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + userToken()))
                // 权限拒绝必须是 HTTP 403 本身，而不是 200 + body code=403。
                // 原来断言 status().isOk() 等于把缺陷固化成了期望；
                // 前端只按状态码判断时，200 会让它把「没权限」渲染成空态。
                .andExpect(status().isForbidden())
                .andExpect(jsonPath("$.code").value(403));
    }

    @Test
    void disable_withAdminToken_returns200() throws Exception {
        mockMvc.perform(delete("/api/v1/admin/fences/1")
                        .header("Authorization", "Bearer " + adminToken()))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.code").value(0));
    }
}
