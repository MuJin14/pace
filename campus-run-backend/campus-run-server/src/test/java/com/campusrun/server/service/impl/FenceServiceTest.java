package com.campusrun.server.service.impl;

import com.campusrun.common.exception.BusinessException;
import com.campusrun.server.cache.FenceCache;
import com.campusrun.server.dto.request.FenceCreateRequest;
import com.campusrun.server.dto.response.FenceResponse;
import com.campusrun.server.entity.CampusFence;
import com.campusrun.server.mapper.CampusFenceMapper;
import com.campusrun.server.model.FenceMatchResult;
import com.campusrun.server.model.TrackPoint;
import com.campusrun.server.service.FenceService;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.context.SpringBootTest;
import org.springframework.test.context.ActiveProfiles;
import org.springframework.transaction.annotation.Transactional;

import java.math.BigDecimal;
import java.util.List;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertFalse;
import static org.junit.jupiter.api.Assertions.assertNotNull;
import static org.junit.jupiter.api.Assertions.assertNull;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.junit.jupiter.api.Assertions.assertTrue;

@SpringBootTest
@ActiveProfiles("test")
@Transactional
class FenceServiceTest {

    @Autowired
    private FenceService fenceService;

    @Autowired
    private CampusFenceMapper fenceMapper;

    @Autowired
    private FenceCache fenceCache;

    @BeforeEach
    void invalidateCache() {
        fenceCache.invalidate();
    }

    private CampusFence insertFence(String name, double lat, double lng, int radius, String ratio) {
        CampusFence fence = new CampusFence();
        fence.setName(name);
        fence.setCenterLat(BigDecimal.valueOf(lat));
        fence.setCenterLng(BigDecimal.valueOf(lng));
        fence.setRadiusMeters(radius);
        fence.setAllowedOutsideRatio(new BigDecimal(ratio));
        fence.setEnabled(1);
        fenceMapper.insert(fence);
        return fence;
    }

    private TrackPoint pt(double lat, double lng) {
        return new TrackPoint(lat, lng, 0L, 10.0);
    }

    @Test
    void evaluate_allInside_valid() {
        insertFence("操场", 39.0, 116.0, 100_000, "0.3000");
        fenceCache.invalidate();

        FenceMatchResult result = fenceService.evaluate(List.of(
                pt(39.0, 116.0), pt(39.001, 116.001), pt(39.002, 116.002)));

        assertFalse(result.invalid());
        assertNotNull(result.fenceId());
        assertTrue(result.outsideRatio().doubleValue() < 0.01);
    }

    @Test
    void fence_evaluate_allOutside_fenceIdNull() {
        insertFence("操场", 39.0, 116.0, 100, "0.3000");
        fenceCache.invalidate();

        FenceMatchResult result = fenceService.evaluate(List.of(
                pt(40.0, 117.0), pt(40.001, 117.001)));

        assertTrue(result.invalid());
        assertNull(result.fenceId());
        assertEquals(0, result.outsideRatio().compareTo(BigDecimal.ONE));
    }

    @Test
    void fence_evaluate_partialInside_matchesFence() {
        CampusFence fence = insertFence("操场", 39.0, 116.0, 100_000, "0.3000");
        fenceCache.invalidate();

        // 4 个点中 3 个在围栏内 -> insideRatio = 0.75 >= 0.7 -> valid，fenceId 匹配
        FenceMatchResult result = fenceService.evaluate(List.of(
                pt(39.0, 116.0), pt(39.001, 116.001), pt(39.002, 116.002),
                pt(40.0, 117.0)));

        assertFalse(result.invalid());
        assertEquals(fence.getId(), result.fenceId());
    }

    @Test
    void evaluate_noEnabledFence_skip() {
        FenceMatchResult result = fenceService.evaluate(List.of(pt(39.0, 116.0), pt(39.1, 116.1)));

        assertFalse(result.invalid());
        assertNull(result.fenceId());
    }

    @Test
    void crud_flow() {
        FenceCreateRequest request = new FenceCreateRequest();
        request.setName("东操场");
        request.setCenterLat(new BigDecimal("39.0000"));
        request.setCenterLng(new BigDecimal("116.0000"));
        request.setRadiusMeters(500);
        request.setAllowedOutsideRatio(new BigDecimal("0.2000"));

        FenceResponse created = fenceService.create(request);
        assertNotNull(created.getId());
        assertEquals(1, created.getEnabled());
        assertEquals("东操场", created.getName());

        FenceResponse fetched = fenceService.get(created.getId());
        assertEquals(created.getId(), fetched.getId());

        List<FenceResponse> list = fenceService.list();
        assertTrue(list.stream().anyMatch(f -> f.getId().equals(created.getId())));

        fenceService.disable(created.getId());
        FenceResponse disabled = fenceService.get(created.getId());
        assertEquals(0, disabled.getEnabled());
    }

    @Test
    void get_notFound_throws() {
        assertThrows(BusinessException.class, () -> fenceService.get(999_999_999L));
    }
}
